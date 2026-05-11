# frozen_string_literal: true

require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'uri'
require 'logger'

module RubyAsterisk
  module ARI
    # WebSocket client for ARI events
    # Connects to the Asterisk ARI WebSocket endpoint to receive real-time events
    class WebSocket
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

      private

      # Build the WebSocket URL
      #
      # @return [String]
      def build_url
        uri = URI.parse(@base_url)
        ws_scheme = uri.scheme == 'https' ? 'wss' : 'ws'
        auth = "#{@api_key}:@"

        "#{ws_scheme}://#{auth}#{uri.host}:#{uri.port}/ari/events?app=#{@app_name}"
      end

      # Establish WebSocket connection
      def establish_connection
        @logger.info "Connecting to ARI WebSocket: app=#{@app_name}"

        url = build_url
        @ws = Faye::WebSocket::Client.new(url)

        setup_event_handlers
      rescue StandardError => e
        @logger.error "Failed to establish connection: #{e.message}"
        schedule_reconnect
      end

      # Setup WebSocket event handlers
      def setup_event_handlers
        @ws.on :open do |_event|
          handle_open
        end

        @ws.on :message do |event|
          handle_message(event)
        end

        @ws.on :close do |event|
          handle_close(event)
        end

        @ws.on :error do |event|
          handle_error(event)
        end
      end

      # Handle WebSocket open event
      def handle_open
        @connected = true
        @reconnect_attempts = 0
        @logger.info 'WebSocket connected successfully'

        start_ping_timer
        @on_connect_callback&.call(self)
      end

      # Handle incoming WebSocket message
      #
      # @param event [Faye::WebSocket::API::Event]
      def handle_message(event)
        data = JSON.parse(event.data)
        event_type = data['type']

        @logger.debug "Received event: #{event_type}"

        # Dispatch to registered callbacks
        dispatch_event(event_type, data)
      rescue JSON::ParserError => e
        @logger.error "Failed to parse message: #{e.message}"
      end

      # Handle WebSocket close event
      #
      # @param event [Faye::WebSocket::API::Event]
      def handle_close(event)
        @connected = false
        stop_ping_timer

        @logger.warn "WebSocket closed: code=#{event.code}, reason=#{event.reason}"

        schedule_reconnect if @should_reconnect
      end

      # Handle WebSocket error event
      #
      # @param event [Faye::WebSocket::API::Event]
      def handle_error(event)
        @logger.error "WebSocket error: #{event.message}"
      end

      # Dispatch event to registered callbacks
      #
      # @param event_type [String] Event type
      # @param data [Hash] Event data
      def dispatch_event(event_type, data)
        # Call specific event handlers
        @callbacks[event_type]&.each do |callback|
          callback.call(data)
        rescue StandardError => e
          @logger.error "Error in event handler for #{event_type}: #{e.message}"
        end

        # Call wildcard handlers (if registered with '*')
        @callbacks['*']&.each do |callback|
          callback.call(data)
        rescue StandardError => e
          @logger.error "Error in wildcard event handler: #{e.message}"
        end
      end

      # Start the ping timer to keep connection alive
      def start_ping_timer
        stop_ping_timer

        @ping_timer = EM::PeriodicTimer.new(@ping_interval) do
          if connected?
            @logger.debug 'Sending ping'
            @ws.ping
          end
        end
      end

      # Stop the ping timer
      def stop_ping_timer
        @ping_timer&.cancel
        @ping_timer = nil
      end

      # Schedule a reconnection attempt
      def schedule_reconnect
        return unless @should_reconnect

        if MAX_RECONNECT_ATTEMPTS && @reconnect_attempts >= MAX_RECONNECT_ATTEMPTS
          @logger.error 'Max reconnection attempts reached, giving up'
          return
        end

        @reconnect_attempts += 1
        @logger.info "Scheduling reconnection attempt #{@reconnect_attempts} in #{@reconnect_delay} seconds"

        stop_reconnect_timer
        @reconnect_timer = EM::Timer.new(@reconnect_delay) do
          establish_connection
        end
      end

      # Stop the reconnect timer
      def stop_reconnect_timer
        @reconnect_timer&.cancel
        @reconnect_timer = nil
      end
    end
  end
end
