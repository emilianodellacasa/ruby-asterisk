# frozen_string_literal: true

require 'ruby-asterisk/version'
require 'ruby-asterisk/request'
require 'ruby-asterisk/response'
require 'ruby-asterisk/response_builder'
require 'ruby-asterisk/ami/promise'

# Commands
Dir[File.join(File.dirname(__FILE__), 'commands', '*.rb')].each { |file| require file }

require 'ruby-asterisk/ami/socket_reader_ractor'
require 'ruby-asterisk/ami/parser_ractor'
require 'timeout'

module RubyAsterisk
  module AMI
    ##
    # Asynchronous AMI client.
    #
    # {#execute} registers a {Promise} for the outgoing command and writes it
    # to the socket, returning the Promise *immediately* without blocking.
    # A background event-loop thread receives parsed messages from the
    # {ParserRactor} and resolves (or rejects) each pending Promise.
    #
    # Callers obtain the response by calling {Promise#value} on the returned
    # Promise, which blocks only until the matching reply arrives (or a
    # per-command timeout fires).
    #
    # Data pipeline:
    #   SocketReaderRactor  -->  ParserRactor  -->  Client event-loop thread
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
        @promises          = {}
        @promises_mutex    = Mutex.new
        @event_loop_thread = nil
      end

      # Connect to the Asterisk AMI server and start the async event loop.
      #
      # @return [true, false]
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

      # Disconnect from Asterisk, stop the event loop, and reject any pending promises.
      #
      # @return [true, false]
      def disconnect
        stop_event_loop
        teardown_ractors
        reject_all_promises(RuntimeError.new('Client disconnected'))
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

      ##
      # Send an AMI command asynchronously.
      #
      # Registers a {Promise}, writes the command to the socket, and returns
      # immediately.  The Promise is resolved by the event-loop thread when
      # Asterisk sends a matching response.
      #
      # @param command [String]  AMI action name (e.g. 'Ping', 'Login')
      # @param options [Hash]    additional AMI headers
      # @return [Promise]        call {Promise#value} to obtain the {Response}
      def execute(command, options = {})
        request = Request.new(command, options)
        promise = Promise.new(action_id: request.action_id, command_type: command, timeout: @timeout)
        @promises_mutex.synchronize { @promises[request.action_id] = promise }
        request.commands.each { |cmd| @reader_ractor.write(cmd) }
        promise
      end

      private

      # -------------------------------------------------------------------------
      # Connection setup
      # -------------------------------------------------------------------------

      def handle_connection_message
        msg = Timeout.timeout(@timeout) { Ractor.receive }
        if msg[:type] == :connected
          self.connected = true
          consume_until_idle
          start_event_loop
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

      # Drain any initial messages (e.g. AMI banner events) that arrive right
      # after the connection is established, before the event loop starts.
      def consume_until_idle(idle_time = 0.5)
        last_message_time = Time.now
        loop do
          msg = Timeout.timeout(0.05) { Ractor.receive }
          dispatch_message(msg)
          last_message_time = Time.now
        rescue Timeout::Error
          break if Time.now - last_message_time > idle_time
        end
      end

      # -------------------------------------------------------------------------
      # Event loop
      # -------------------------------------------------------------------------

      def start_event_loop
        @event_loop_thread = Thread.new do
          loop do
            msg = Ractor.receive
            break if msg[:type] == :stop

            dispatch_message(msg)
          end
        end
      end

      # Send a sentinel :stop into Ractor.current's inbox so the event-loop
      # thread unblocks and exits cleanly.
      def stop_event_loop
        return unless @event_loop_thread&.alive?

        Ractor.current.send({ type: :stop }.freeze)
        @event_loop_thread.join(1)
        @event_loop_thread = nil
      end

      def teardown_ractors
        @reader_ractor&.stop
        @reader_ractor = nil

        @parser_ractor&.stop
        @parser_ractor = nil
      end

      # -------------------------------------------------------------------------
      # Message dispatch
      # -------------------------------------------------------------------------

      def dispatch_message(msg)
        case msg[:type]
        when :response
          resolve_promise(msg[:action_id], msg[:raw])
        when :event
          # Async events received outside of a command cycle — ignored for now.
        when :error
          reject_all_promises(RuntimeError.new("Error from Ractor: #{msg[:message]}"))
        when :disconnected
          reject_all_promises(RuntimeError.new("Disconnected: #{msg[:reason]}"))
        end
      end

      def resolve_promise(action_id, raw_data)
        promise = @promises_mutex.synchronize { @promises.delete(action_id) }
        promise&.resolve(raw_data)
      end

      def reject_all_promises(error)
        promises = @promises_mutex.synchronize do
          @promises.values.tap { @promises.clear }
        end
        promises.each { |p| p.reject(error) }
      end
    end
  end
end
