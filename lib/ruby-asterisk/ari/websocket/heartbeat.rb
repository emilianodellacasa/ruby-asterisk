# frozen_string_literal: true

module RubyAsterisk
  module ARI
    class WebSocket
      # Ping keep-alive timer and interruptible waits for ARI WebSocket
      module Heartbeat
        private

        # Start the ping timer to keep connection alive
        def start_ping_timer
          stop_ping_timer

          token = @ping_token = Object.new
          @ping_thread = Thread.new { ping_loop(token) }
        end

        # Send a ping every @ping_interval seconds until the token is revoked
        def ping_loop(token)
          loop do
            wait_or_wake(@ping_interval)
            break unless token.equal?(@ping_token)
            next unless connected?

            @logger.debug 'Sending ping'
            send_ping
          end
        end

        def send_ping
          driver = @driver
          @driver_monitor.synchronize { driver&.ping }
        rescue IOError, SystemCallError
          nil
        end

        # Stop the ping timer
        def stop_ping_timer
          @ping_token = nil
          @ping_thread = nil
          wake_sleepers
        end

        # Interruptible sleep: returns early when wake_sleepers is called
        def wait_or_wake(seconds)
          @wake_mutex.synchronize { @wake_cv.wait(@wake_mutex, seconds) }
        end

        def wake_sleepers
          @wake_mutex.synchronize { @wake_cv.broadcast }
        end
      end
    end
  end
end
