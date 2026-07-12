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

        # Main loop of the connection thread: connect, read until the
        # connection drops, then reconnect while auto-reconnect is enabled.
        def connection_loop
          loop do
            run_connection
            break unless @should_reconnect
            break unless wait_before_reconnect
          end
        end

        # Run a single connection: establish it and read until it drops.
        def run_connection
          establish_connection
        rescue StandardError => e
          @logger.error "Failed to establish connection: #{e.message}"
        else
          read_loop
        ensure
          cleanup_connection
        end

        # Establish WebSocket connection
        def establish_connection
          @logger.info "Connecting to ARI WebSocket: app=#{@app_name}"

          @socket = open_socket(URI.parse(@base_url))
          @driver = ::WebSocket::Driver.client(SocketAdapter.new(build_url, @socket))

          setup_event_handlers
          @driver.start
        end

        # Open a TCP socket, wrapped in TLS when the base URL is https
        def open_socket(uri)
          tcp = TCPSocket.new(uri.host, uri.port)
          tcp.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
          return tcp unless uri.scheme == 'https'

          context = OpenSSL::SSL::SSLContext.new
          context.set_params
          ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
          ssl.hostname = uri.host
          ssl.sync_close = true
          ssl.connect
          ssl
        end

        # Setup WebSocket event handlers
        def setup_event_handlers
          @driver.on(:open) { |_event| handle_open }
          @driver.on(:message) { |event| handle_message(event) }
          @driver.on(:close) { |event| handle_close(event) }
          @driver.on(:error) { |event| handle_error(event) }
        end

        # Feed incoming bytes to the driver until the socket closes
        def read_loop
          loop do
            chunk = @socket.readpartial(4096)
            @driver_monitor.synchronize { @driver.parse(chunk) }
          end
        rescue IOError, SystemCallError
          handle_connection_lost
        end

        # The socket dropped without a WebSocket close frame
        def handle_connection_lost
          return unless @connected

          @connected = false
          stop_ping_timer
          @logger.warn 'WebSocket connection lost'
        end

        # Release per-connection resources after the read loop exits
        def cleanup_connection
          stop_ping_timer
          close_socket
          @driver = nil
          @socket = nil
          @connected = false
        end

        # Wait before the next reconnection attempt
        #
        # @return [Boolean] false when reconnection must stop
        def wait_before_reconnect
          if MAX_RECONNECT_ATTEMPTS && @reconnect_attempts >= MAX_RECONNECT_ATTEMPTS
            @logger.error 'Max reconnection attempts reached, giving up'
            return false
          end

          @reconnect_attempts += 1
          @logger.info "Scheduling reconnection attempt #{@reconnect_attempts} in #{@reconnect_delay} seconds"

          wait_or_wake(@reconnect_delay)
          @should_reconnect
        end

        # Send a close frame (if the connection is open) and close the socket
        def close_connection
          driver = @driver
          @driver_monitor.synchronize { driver.close } if driver && driver.state == :open
        rescue StandardError
          nil
        ensure
          close_socket
        end

        def close_socket
          @socket&.close
        rescue StandardError
          nil
        end
      end
    end
  end
end
