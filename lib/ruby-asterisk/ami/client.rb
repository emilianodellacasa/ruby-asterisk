# frozen_string_literal: true

require 'ruby-asterisk/version'
require 'ruby-asterisk/request'
require 'ruby-asterisk/response'
require 'ruby-asterisk/response_builder'

# Commands
Dir[File.join(File.dirname(__FILE__), 'commands', '*.rb')].each { |file| require file }

require 'ruby-asterisk/ami/socket_reader_ractor'
require 'ruby-asterisk/ami/parser_ractor'
require 'timeout'

module RubyAsterisk
  module AMI
    ##
    # Ruby-asterisk main class.
    #
    # Data pipeline:
    #   SocketReaderRactor  -->  ParserRactor  -->  Client (Ractor.current)
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

      attr_accessor :host, :port, :connected, :timeout, :wait_time

      def initialize(host:, port:)
        self.host      = host.to_s
        self.port      = port.to_i
        self.connected = false
        @timeout           = 5
        @wait_time         = 0.1
        @reader_ractor     = nil
        @parser_ractor     = nil
        @pending_responses = []
      end

      def connect
        @parser_ractor = ParserRactor.new(Ractor.current)
        @reader_ractor = SocketReaderRactor.new(host, port)
        @reader_ractor.start(consumer: @parser_ractor.input)
        handle_connection_message
      rescue StandardError => e
        puts "Connection error: #{e.message}"
        self.connected = false
        false
      end

      def disconnect
        @reader_ractor&.stop
        @reader_ractor = nil

        @parser_ractor&.stop
        @parser_ractor = nil

        self.connected = false
        true
      rescue StandardError => e
        puts e
        false
      end

      def login(username:, secret:)
        connect unless connected
        execute 'Login', { 'Username' => username, 'Secret' => secret, 'Event' => 'On' }
      end

      def logoff
        execute 'Logoff'
      end

      def execute(command, options = {})
        request = Request.new(command, options)
        request.commands.each { |cmd| @reader_ractor.write(cmd) }
        response_data = wait_for_response(request.action_id)
        ResponseBuilder.new.tap do |builder|
          builder.type         = command
          builder.raw_response = response_data
        end.build
      end

      private

      def handle_connection_message
        msg = Timeout.timeout(@timeout) { Ractor.receive }
        if msg[:type] == :connected
          self.connected = true
          consume_until_idle
          return true
        end
        handle_connection_error(msg)
        false
      rescue Timeout::Error
        puts "Timeout connecting to #{host}:#{port}"
        self.connected = false
        false
      end

      def handle_connection_error(msg)
        return unless msg[:type] == :error

        puts "Connection error: #{msg[:message]}"
        self.connected = false
      end

      def consume_until_idle(idle_time = 0.5)
        last_message_time = Time.now
        loop do
          msg = Timeout.timeout(0.05) { Ractor.receive }
          process_incoming_message(msg)
          last_message_time = Time.now
        rescue Timeout::Error
          break if Time.now - last_message_time > idle_time
        end
      end

      def wait_for_response(action_id)
        start_time = Time.now

        if (idx = @pending_responses.index { |m| m[:action_id] == action_id })
          return @pending_responses.delete_at(idx)[:raw]
        end

        loop do
          raise "Timeout waiting for response (ActionID: #{action_id})" if Time.now - start_time > @timeout

          wait_for_more_data(start_time)

          if (idx = @pending_responses.index { |m| m[:action_id] == action_id })
            return @pending_responses.delete_at(idx)[:raw]
          end
        end
      end

      def wait_for_more_data(start_time)
        wait_remaining = @timeout - (Time.now - start_time)
        msg = Timeout.timeout([wait_remaining, @wait_time].min) { Ractor.receive }
        process_incoming_message(msg)
      rescue Timeout::Error
        # Loop again
      end

      def process_incoming_message(msg)
        case msg[:type]
        when :response
          @pending_responses << msg
        when :event
          # Async events received outside of a command cycle — ignored for now.
        when :error
          raise "Error from Ractor: #{msg[:message]}"
        when :disconnected
          raise "Disconnected: #{msg[:reason]}"
        end
      end
    end
  end
end
