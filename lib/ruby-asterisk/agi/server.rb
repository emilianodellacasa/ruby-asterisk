# frozen_string_literal: true

require 'socket'
require 'logger'
require 'async'
require_relative 'session'
require_relative '../../ruby-asterisk/error'

module RubyAsterisk
  module AGI
    # FastAGI TCP server backed by an Async Fiber scheduler.
    #
    # Each incoming Asterisk connection is handled in its own Fiber, so all
    # concurrent sessions share a single OS thread and their socket IO yields
    # the Fiber rather than blocking.
    #
    # Usage:
    #   server = RubyAsterisk::AGI::Server.new('0.0.0.0', 4573)
    #   server.handle { |session| session.answer }
    #   server.run         # blocks until server.stop is called
    class Server
      attr_reader :host, :port, :running

      alias running? running

      def initialize(host, port, logger: Logger.new($stdout))
        @host    = host
        @port    = port.to_i
        @logger  = logger
        @handler = nil
        @running = false
        @server  = nil
      end

      # Register the per-connection handler block.
      #
      # @yield [RubyAsterisk::AGI::Session]
      # @return [self]
      def handle(&block)
        @handler = block
        self
      end

      # Start accepting connections (blocks until {#stop} is called).
      #
      # @raise [RubyAsterisk::Error] if no handler has been registered
      def run
        raise Error, 'No handler registered' unless @handler

        Sync do |parent|
          @server  = TCPServer.new(@host, @port)
          @port    = @server.addr[1]
          @running = true
          @logger.info("AGI server listening on #{@host}:#{@port}")
          accept_loop(parent)
        end
      ensure
        @running = false
        close_server
      end

      # Signal the server to stop accepting new connections.
      # Active sessions continue until they finish naturally.
      def stop
        return unless @running

        @running = false
        close_server
      end

      private

      def accept_loop(parent)
        loop do
          socket = @server.accept
          parent.async { serve(socket) }
        end
      rescue IOError, Errno::EBADF
        # Server socket closed via stop — normal shutdown
      end

      def serve(socket)
        session = Session.new(socket, logger: @logger)
        session.read_env
        @handler.call(session)
      rescue StandardError => e
        @logger.error("AGI session error: #{e.message}")
      ensure
        socket.close rescue nil # rubocop:disable Style/RescueModifier
      end

      def close_server
        @server&.close
        @server = nil
      rescue StandardError
        nil
      end
    end
  end
end
