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
          user, pass = @api_key.to_s.split(':', 2)
          auth = "#{encode_userinfo(user)}:#{encode_userinfo(pass)}@"
          app = URI.encode_www_form_component(@app_name)

          "#{ws_scheme}://#{auth}#{uri.host}:#{uri.port}/ari/events?app=#{app}"
        end

        # URL-encode a userinfo component (user or password), leaving nil as ''
        def encode_userinfo(component)
          URI::DEFAULT_PARSER.escape(component.to_s, /[^A-Za-z0-9\-._~]/)
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
          tcp.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
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

        # Feed incoming bytes to the driver until the socket closes.
        #
        # driver.parse dispatches :open/:message synchronously (under
        # @driver_monitor); handlers only enqueue closures via #defer so user
        # callbacks run here, after the monitor is released.
        def read_loop
          loop do
            chunk = @socket.readpartial(4096)
            pending = []
            @driver_monitor.synchronize do
              @pending_dispatch = pending
              begin
                @driver.parse(chunk)
              ensure
                @pending_dispatch = nil
              end
            end
            dispatch_pending(pending)
          end
        rescue IOError, SystemCallError
          handle_connection_lost
        end

        # Run deferred callbacks, containing any exception so it never kills the loop.
        def dispatch_pending(callbacks)
          callbacks.each do |callback|
            callback.call
          rescue StandardError => e
            @logger.error "Error dispatching WebSocket event: #{e.message}"
          end
        end

        # Enqueue a closure to run after the driver monitor is released. When
        # invoked outside an active parse (no dispatch buffer), run immediately.
        def defer(&block)
          if @pending_dispatch
            @pending_dispatch << block
          else
            yield
          end
        end

        # Release per-connection resources after the read loop exits
        def cleanup_connection
          stop_ping_timer
          close_socket
          @driver = nil
          @socket = nil
          @connected = false
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
