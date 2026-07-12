# frozen_string_literal: true

require 'ruby-asterisk/version'
require 'ruby-asterisk/error'
require 'ruby-asterisk/request'
require 'ruby-asterisk/response'
require 'ruby-asterisk/response_builder'
require 'ruby-asterisk/ami/promise'
require 'ruby-asterisk/ami/reactor'

# Commands
Dir[File.join(File.dirname(__FILE__), 'commands', '*.rb')].each { |file| require file }

module RubyAsterisk
  module AMI
    ##
    # Asynchronous AMI client.
    #
    # {#execute} registers a {Promise} for the outgoing command and writes it
    # to the socket via the internal {Reactor}, returning the Promise immediately
    # without blocking.  Callers obtain the response by calling {Promise#value}
    # on the returned Promise, which blocks only until the matching reply arrives
    # (or a per-command timeout fires).
    #
    # Data pipeline:
    #   Client (external thread)
    #     → Reactor#send_command (Thread::Queue + IO.pipe doorbell)
    #     → intake Fiber → socket write
    #     → socket read → reader Fiber → Parser
    #     → dispatcher → Promise#resolve (Mutex+CV)
    #     → Client#execute caller (blocks on Promise#value)
    #
    class Client
      include Commands::System
      include Commands::Channel
      include Commands::Conference
      include Commands::Extension
      include Commands::Queue
      include Commands::Mailbox
      include Commands::Sip
      include Commands::Monitor

      attr_accessor :host, :port, :connected, :timeout

      def initialize(host:, port:)
        self.host      = host.to_s
        self.port      = port.to_i
        self.connected = false
        @timeout       = 5
        @reactor       = nil
      end

      # Connect to the Asterisk AMI server and start the async reactor.
      #
      # @return [true, false]
      def connect
        @reactor = Reactor.new(host, port,
                               on_event: method(:handle_event),
                               on_disconnect: method(:handle_disconnect))
        @reactor.start
        self.connected = true
        true
      rescue StandardError => e
        puts "Connection error: #{e.message}"
        @reactor = nil
        self.connected = false
        false
      end

      # Disconnect from Asterisk, stop the reactor, and reject pending promises.
      #
      # @return [true, false]
      def disconnect
        @reactor&.stop
        @reactor&.reject_all_promises(RuntimeError.new('Client disconnected'))
        @reactor = nil
        self.connected = false
        true
      rescue StandardError => e
        puts e
        false
      end

      def login(username:, secret:)
        connect unless connected
        raise Error, "Unable to connect to AMI at #{host}:#{port}" unless connected

        execute 'Login', { 'Username' => username, 'Secret' => secret, 'Event' => 'On' }
      end

      def logoff
        execute 'Logoff'
      end

      ##
      # Send an AMI command asynchronously.
      #
      # @param command [String]  AMI action name (e.g. 'Ping', 'Login')
      # @param options [Hash]    additional AMI headers
      # @param timeout [Numeric] seconds {Promise#value} waits by default for
      #   this command only (does not affect other commands)
      # @return [Promise]        call {Promise#value} to obtain the {Response}
      # @raise [RubyAsterisk::Error] if the client is not connected
      def execute(command, options = {}, timeout: @timeout)
        raise Error, 'Not connected to AMI' unless @reactor

        request = Request.new(command, options)
        promise = Promise.new(action_id: request.action_id, command_type: command, timeout: timeout)
        promise.on_timeout = -> { @reactor&.unregister_promise(request.action_id) }
        @reactor.register_promise(request.action_id, promise)
        # Push the whole frame in one operation so commands issued from concurrent
        # threads cannot interleave their header lines on the wire.
        @reactor.send_command(request.commands.join)
        promise
      end

      private

      def handle_event(_event)
        # Async events received outside a command cycle — available for future use.
      end

      def handle_disconnect
        self.connected = false
      end
    end
  end
end
