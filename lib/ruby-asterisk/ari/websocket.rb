# frozen_string_literal: true

require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'uri'
require 'logger'
require_relative 'websocket/connection'
require_relative 'websocket/event_handlers'

module RubyAsterisk
  module ARI
    # WebSocket client for ARI events
    # Connects to the Asterisk ARI WebSocket endpoint to receive real-time events
    class WebSocket
      include Connection
      include EventHandlers
      attr_reader :url, :app_name, :callbacks, :connected

      # Ping interval in seconds to keep connection alive
      PING_INTERVAL = 30

      # Reconnect delay in seconds
      RECONNECT_DELAY = 5

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
        @ws = nil
        @connected = false
        @ping_timer = nil
        @reconnect_timer = nil
        @should_reconnect = options.fetch(:auto_reconnect, true)
        @reconnect_attempts = 0
        @logger = options[:logger] || Logger.new($stdout)
        @ping_interval = options.fetch(:ping_interval, PING_INTERVAL)
        @reconnect_delay = options.fetch(:reconnect_delay, RECONNECT_DELAY)
        @em_thread = nil
      end

      # Connect to the WebSocket endpoint
      #
      # @yield [self] Block called when connection is established
      # @return [self]
      def connect(&block)
        @on_connect_callback = block

        # Start EventMachine if not already running
        unless EM.reactor_running?
          @em_thread = Thread.new { EM.run }
          sleep 0.1 until EM.reactor_running?
        end

        EM.next_tick { establish_connection }

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
        stop_reconnect_timer

        if @ws
          @ws.close
          @ws = nil
        end

        @connected = false
        @logger.info 'WebSocket disconnected'
        self
      end

      # Check if WebSocket is connected
      #
      # @return [Boolean]
      def connected?
        @connected && @ws && @ws.ready_state == Faye::WebSocket::API::OPEN
      end

      # Send a message through the WebSocket
      #
      # @param message [Hash, String] Message to send (will be converted to JSON if Hash)
      # @return [Boolean] true if sent successfully
      def send_message(message)
        return false unless connected?

        data = message.is_a?(Hash) ? JSON.generate(message) : message
        @ws.send(data)
        true
      end

    end
  end
end
