# frozen_string_literal: true

require 'ruby-asterisk/version'
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
        @reactor = Reactor.new(host, port, on_event: method(:handle_event))
        @reactor.start
        self.connected = true
        true
      rescue StandardError => e
        puts "Connection error: #{e.message}"
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
      # @return [Promise]        call {Promise#value} to obtain the {Response}
      def execute(command, options = {})
        request = Request.new(command, options)
        promise = Promise.new(action_id: request.action_id, command_type: command, timeout: @timeout)
        @reactor.register_promise(request.action_id, promise)
        request.commands.each { |cmd| @reactor.send_command(cmd) }
        promise
      end

      private

      def handle_event(_event)
        # Async events received outside a command cycle — available for future use.
      end
    end
  end
end
