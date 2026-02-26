# frozen_string_literal: true

require 'socket'

module RubyAsterisk
  # Dedicated Ractor for reading from the Asterisk socket
  class SocketReaderRactor
    attr_reader :host, :port

    # Define the Ractor logic as a constant Proc to ensure isolation
    RACTOR_LOGIC = Proc.new do
      loop do
        message = Ractor.receive
        
        if message[:type] == :connect
          h = message[:host]
          p = message[:port]
          consumer = message[:consumer]
          
          socket = nil
          reader_thread = nil

          begin
            socket = TCPSocket.new(h, p)
            socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)

            # Notify connected
            consumer.send({ type: :connected, host: h, port: p }.freeze)

            # Spawn reader thread inside Ractor
            # This thread reads from socket and sends to consumer
            reader_thread = Thread.new do
              begin
                loop do
                  chunk = socket.readpartial(4096)
                  consumer.send({ type: :data, data: chunk.freeze }.freeze)
                end
              rescue EOFError
                consumer.send({ type: :disconnected, reason: "EOF from server" }.freeze)
              rescue StandardError => e
                consumer.send({ type: :error, message: e.message }.freeze)
              end
            end

            # Main Ractor thread handles mailbox (Writes/Stops)
            loop do
              msg = Ractor.receive
              case msg[:type]
              when :write
                begin
                  socket.write(msg[:data])
                rescue StandardError => e
                  consumer.send({ type: :error, message: "Write failed: #{e.message}" }.freeze)
                end
              when :stop
                reader_thread.kill if reader_thread
                socket.close rescue nil
                break # Break inner loop
              end
            end
            
            # If we break inner loop, we break outer loop too (terminate Ractor logic)
            break
            
          rescue StandardError => e
            consumer.send({ type: :error, message: "Connection failed: #{e.message}" }.freeze)
          ensure
            reader_thread&.kill
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
      @pipe = Ractor.new(&RACTOR_LOGIC)
    end

    def start(consumer: nil)
      target = consumer || Ractor.current
      @pipe.send({ type: :connect, host: @host, port: @port, consumer: target }.freeze)
    end
    
    def write(data)
      @pipe.send({ type: :write, data: data.freeze }.freeze)
    end

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
