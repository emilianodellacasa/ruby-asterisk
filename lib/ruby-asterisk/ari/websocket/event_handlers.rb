# frozen_string_literal: true

module RubyAsterisk
  module ARI
    class WebSocket
      # Event handling for ARI WebSocket
      module EventHandlers
        private

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
      end
    end
  end
end
