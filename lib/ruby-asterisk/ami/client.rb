# frozen_string_literal: true

require 'ruby-asterisk/version'
require 'ruby-asterisk/request'
require 'ruby-asterisk/response'
require 'ruby-asterisk/response_builder'

# Commands
Dir[File.join(File.dirname(__FILE__), 'commands', '*.rb')].each { |file| require file }

require 'ruby-asterisk/ami/socket_reader_ractor'
require 'timeout'

module RubyAsterisk
  module AMI
    ##
    # Ruby-asterisk main classes
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
        self.host = host.to_s
        self.port = port.to_i
        self.connected = false
        @timeout = 5
        @wait_time = 0.1
        @reader_ractor = nil
        @response_buffer = +''
      end

      def connect
        @reader_ractor = SocketReaderRactor.new(host, port)
        @reader_ractor.start(consumer: Ractor.current)
        handle_connection_message
      rescue StandardError => e
        puts "Connection error: #{e.message}"
        self.connected = false
        false
      end

      def disconnect
        @reader_ractor&.stop
        @reader_ractor = nil
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
          builder.type = command
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
        pattern = /ActionID: #{Regexp.escape(action_id)}.*?\r\n\r\n/m
        loop do
          if (match = @response_buffer.match(pattern))
            return extract_response_from_buffer(match)
          end
          raise "Timeout waiting for response (ActionID: #{action_id})" if Time.now - start_time > @timeout

          wait_for_more_data(start_time)
        end
      end

      def extract_response_from_buffer(match)
        response_data = match[0]
        @response_buffer.sub!(response_data, '')
        response_data
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
        when :data
          @response_buffer << msg[:data]
        when :error
          raise "Error from Ractor: #{msg[:message]}"
        when :disconnected
          raise "Disconnected: #{msg[:reason]}"
        end
      end
    end
  end
end
