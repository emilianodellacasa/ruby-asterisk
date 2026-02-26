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
        # Create and start the socket reader Ractor
        @reader_ractor = SocketReaderRactor.new(host, port)
        @reader_ractor.start(consumer: Ractor.current)
        
        # Wait for connection confirmation
        begin
          msg = Timeout.timeout(@timeout) { Ractor.receive }
          if msg[:type] == :connected
            self.connected = true
            # Consume welcome message
            consume_until_idle
            return true
          elsif msg[:type] == :error
            puts "Connection error: #{msg[:message]}"
            self.connected = false
            return false
          end
        rescue Timeout::Error
          puts "Timeout connecting to #{host}:#{port}"
          self.connected = false
          return false
        end
        
        false
      rescue StandardError => e
        puts "Connection error: #{e.message}"
        self.connected = false
        false
      end

      def disconnect
        if @reader_ractor
          @reader_ractor.stop
          # Wait for disconnected? No need.
          @reader_ractor = nil
        end
        
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

      # Expose execute for commands mixins
      def execute(command, options = {})
        request = Request.new(command, options)
        
        # Send commands via Ractor
        request.commands.each do |cmd|
          @reader_ractor.write(cmd)
        end
        
        # Wait for response with ActionID
        response_data = wait_for_response(request.action_id)
        
        # Build response
        builder = ResponseBuilder.new
        builder.type = command
        builder.raw_response = response_data
        builder.build
      end

      private

      def consume_until_idle(idle_time = 0.5)
        # Consume any pending messages until idle
        last_message_time = Time.now
        
        loop do
          begin
            # Quick check for messages
            msg = Timeout.timeout(0.05) { Ractor.receive }
            
            case msg[:type]
            when :data
              @response_buffer << msg[:data]
              last_message_time = Time.now
            when :error
              # Log error but continue?
            when :disconnected
              raise "Disconnected"
            end
          rescue Timeout::Error
            # No message received
            break if Time.now - last_message_time > idle_time
          end
        end
      end

      def wait_for_response(action_id)
        start_time = Time.now
        
        # Pattern to match complete response with specific ActionID
        # Using simple regex for now
        pattern = /ActionID: #{Regexp.escape(action_id)}.*?\r\n\r\n/m
        
        loop do
          # Check buffer
          if match = @response_buffer.match(pattern)
            response_data = match[0]
            # Remove ONLY the matched part
            # Be careful with sub! which replaces first occurrence
            @response_buffer.sub!(response_data, '')
            return response_data
          end
          
          # Check timeout
          if Time.now - start_time > @timeout
            raise "Timeout waiting for response (ActionID: #{action_id})"
          end
          
          # Wait for more data
          begin
            # Blocking wait with timeout
            wait_remaining = @timeout - (Time.now - start_time)
            msg = Timeout.timeout([wait_remaining, @wait_time].min) { Ractor.receive }
            
            case msg[:type]
            when :data
              @response_buffer << msg[:data]
            when :error
              raise "Error from Ractor: #{msg[:message]}"
            when :disconnected
              raise "Disconnected: #{msg[:reason]}"
            end
          rescue Timeout::Error
            # Just loop again to check buffer/timeout
          end
        end
      end
    end
  end
end
