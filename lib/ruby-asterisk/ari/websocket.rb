# frozen_string_literal: true

require 'websocket/driver'
require 'socket'
require 'openssl'
require 'json'
require 'uri'
require 'logger'
require 'monitor'
require_relative 'websocket/socket_adapter'
require_relative 'websocket/connection'
require_relative 'websocket/reconnect'
require_relative 'websocket/heartbeat'
require_relative 'websocket/event_handlers'

module RubyAsterisk
  module ARI
    # WebSocket client for ARI events
    # Connects to the Asterisk ARI WebSocket endpoint to receive real-time events
    #
    # I/O model (no EventMachine): the WebSocket protocol is handled by the pure
    # Ruby websocket-driver gem over a plain TCPSocket (SSLSocket for wss).
    #
    #   connection_thread — owns the socket lifecycle: connects, runs the read
    #                       loop (readpartial -> driver.parse -> callbacks), and
    #                       re-connects after a drop while auto-reconnect is on.
    #
    #   ping_thread       — started when the connection opens; wakes every
    #                       ping_interval seconds and sends a WebSocket ping.
    #
    # Event callbacks execute in the connection thread. All driver calls are
    # serialized through a reentrant Monitor so send_message? is safe from any
    # thread.
    class WebSocket
      include Connection
      include Reconnect
      include Heartbeat
      include EventHandlers

      attr_reader :url, :app_name, :callbacks, :connected

      # Ping interval in seconds to keep connection alive
      PING_INTERVAL = 30

      # Reconnect delay in seconds (base for exponential backoff)
      RECONNECT_DELAY = 5

      # Upper bound for the exponential reconnect backoff, in seconds
      MAX_RECONNECT_DELAY = 60

      # Maximum reconnection attempts (nil for infinite)
      MAX_RECONNECT_ATTEMPTS = nil

      # Initialize a new WebSocket client
      #
      # @param base_url [String] Base URL of the Asterisk server (e.g., 'http://localhost:8088')
      # @param api_key [String] API key for authentication
      # @param app_name [String] Stasis application name
      # @param options [Hash] Additional options
      # @option options [Logger] :logger Logger instance for debugging
      # @option options [Integer] :ping_interval Ping interval in seconds (default: 30)
      # @option options [Boolean] :auto_reconnect Enable auto-reconnect (default: true)
      # @option options [Integer] :reconnect_delay Delay between reconnection attempts (default: 5)
      def initialize(base_url, api_key, app_name, options = {})
        @base_url = base_url
        @api_key = api_key
        @app_name = app_name
        @callbacks = {}
        @connected = false
        @should_reconnect = options.fetch(:auto_reconnect, true)
        @reconnect_attempts = 0
        @logger = options[:logger] || Logger.new($stdout)
        @ping_interval = options.fetch(:ping_interval, PING_INTERVAL)
        @reconnect_delay = options.fetch(:reconnect_delay, RECONNECT_DELAY)
        initialize_io_state
      end

      # Connect to the WebSocket endpoint
      #
      # @yield [self] Block called when connection is established
      # @return [self]
      def connect(&block)
        @on_connect_callback = block
        @connection_thread = Thread.new { connection_loop }
        self
      end

      # Register a callback for a specific event type
      #
      # @param event_type [String, Symbol] Event type to listen for (e.g., 'StasisStart')
      # @param block [Proc] Block to execute when event is received
      # @return [self]
      def on(event_type, &block)
        @callbacks[event_type.to_s] = [] unless @callbacks.key?(event_type.to_s)
        @callbacks[event_type.to_s] << block
        self
      end

      # Disconnect from the WebSocket
      #
      # @return [self]
      def disconnect
        @should_reconnect = false
        stop_ping_timer
        close_connection
        wake_sleepers

        thread = @connection_thread
        @connection_thread = nil
        thread&.join(2) unless thread == Thread.current

        @connected = false
        @logger.info 'WebSocket disconnected'
        self
      end

      # Check if WebSocket is connected
      #
      # @return [Boolean]
      def connected?
        !!(@connected && @driver && @driver.state == :open)
      end

      # Send a message through the WebSocket
      #
      # @param message [Hash, String] Message to send (will be converted to JSON if Hash)
      # @return [Boolean] true if sent successfully
      def send_message?(message)
        driver = @driver
        return false unless @connected && driver && driver.state == :open

        data = message.is_a?(Hash) ? JSON.generate(message) : message
        @driver_monitor.synchronize { driver.text(data) }
        true
      rescue IOError, SystemCallError
        false
      end

      private

      def initialize_io_state
        @driver = nil
        @socket = nil
        @connection_thread = nil
        @ping_thread = nil
        @ping_token = nil
        @awaiting_pong = false
        @pending_dispatch = nil
        @driver_monitor = Monitor.new
        @wake_mutex = Mutex.new
        @wake_cv = ConditionVariable.new
      end
    end
  end
end
