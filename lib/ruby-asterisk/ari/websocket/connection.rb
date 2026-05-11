# frozen_string_literal: true

module RubyAsterisk
  module ARI
    class WebSocket
      # Connection management for ARI WebSocket
      module Connection
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
end
