# frozen_string_literal: true

require 'socket'

module RubyAsterisk
  # Dedicated Ractor for reading from the Asterisk socket
  class SocketReaderRactor
    attr_reader :host, :port

    # Define the Ractor logic as a constant Proc to ensure isolation
    RACTOR_LOGIC = Proc.new do
      loop do
        # receive block
        message = Ractor.receive
        
        if message[:type] == :connect
          # Local variables inside block
          h = message[:host]
          p = message[:port]
          consumer = message[:consumer]
          
          begin
            # Socket operations
            socket = TCPSocket.new(h, p)
            # Set keepalive
            socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)

            # Send connected message to consumer
            consumer.send({ type: :connected, host: h, port: p }.freeze)

            # Read loop
            loop do
              ready = IO.select([socket], nil, nil, 0.1)
              
              if ready
                begin
                  chunk = socket.read_nonblock(4096)
                  consumer.send({ type: :data, data: chunk.freeze }.freeze)
                rescue IO::WaitReadable
                  # Retry
                  next
                rescue EOFError
                  consumer.send({ type: :disconnected, reason: "EOF from server" }.freeze)
                  break
                rescue StandardError => e
                  consumer.send({ type: :error, message: e.message }.freeze)
                  break
                end
              end
            end
          rescue StandardError => e
            consumer.send({ type: :error, message: "Connection failed: #{e.message}" }.freeze)
          ensure
            # Ensure socket closed
            socket&.close rescue nil
          end
        elsif message[:type] == :stop
          break
        end
      end
    end

    def initialize(host, port)
      @host = host
      @port = port
      # Create Ractor from the isolated Proc
      @pipe = Ractor.new(&RACTOR_LOGIC)
    end

    def start(consumer: nil)
      # Pass specified consumer or current Ractor
      target = consumer || Ractor.current
      @pipe.send({ type: :connect, host: @host, port: @port, consumer: target }.freeze)
    end
    
    # Optional helper: only useful if consumer is Ractor.current
    def take
      Timeout.timeout(5) { Ractor.receive }
    rescue Timeout::Error
      { type: :timeout, message: "Timed out waiting for message" }
    end

    def stop
      @pipe.send({ type: :stop }.freeze)
    end
  end
end
