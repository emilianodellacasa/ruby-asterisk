# frozen_string_literal: true

module RubyAsterisk
  module ARI
    class WebSocket
      # Reconnection lifecycle for ARI WebSocket: the connection-thread loop and
      # the exponential backoff between attempts.
      module Reconnect
        private

        # Main loop of the connection thread: connect, read until the
        # connection drops, then reconnect while auto-reconnect is enabled.
        def connection_loop
          loop do
            run_connection
            break unless @should_reconnect
            break unless wait_before_reconnect
          end
        end

        # The socket dropped without a WebSocket close frame
        def handle_connection_lost
          return unless @connected

          @connected = false
          stop_ping_timer
          @logger.warn 'WebSocket connection lost'
        end

        # Wait before the next reconnection attempt.
        #
        # @return [Boolean] false when reconnection must stop
        def wait_before_reconnect
          if MAX_RECONNECT_ATTEMPTS && @reconnect_attempts >= MAX_RECONNECT_ATTEMPTS
            @logger.error 'Max reconnection attempts reached, giving up'
            return false
          end

          @reconnect_attempts += 1
          delay = reconnect_backoff_delay
          @logger.info "Scheduling reconnection attempt #{@reconnect_attempts} in #{delay} seconds"

          wait_or_wake(delay)
          @should_reconnect
        end

        # Exponential backoff capped at MAX_RECONNECT_DELAY
        def reconnect_backoff_delay
          [@reconnect_delay * (2**(@reconnect_attempts - 1)), MAX_RECONNECT_DELAY].min
        end
      end
    end
  end
end
