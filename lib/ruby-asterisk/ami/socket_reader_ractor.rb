# frozen_string_literal: true

require 'socket'

module RubyAsterisk
  # Dedicated Ractor for reading from the Asterisk socket
  class SocketReaderRactor
    attr_reader :host, :port

    # Defines the reader thread logic
    def self.reader_loop(socket, consumer)
      loop do
        chunk = socket.readpartial(4096)
        consumer.send({ type: :data, data: chunk.freeze }.freeze)
      end
    rescue EOFError
      consumer.send({ type: :disconnected, reason: 'EOF from server' }.freeze)
    rescue StandardError => e
      consumer.send({ type: :error, message: e.message }.freeze)
    end

    # Defines the main writer/control loop logic
    def self.writer_loop(socket, consumer, reader_thread)
      loop do
        msg = Ractor.receive
        case msg[:type]
        when :write
          handle_write(socket, consumer, msg)
        when :stop
          reader_thread&.kill
          close_socket(socket)
          break
        end
      end
    end

    def self.handle_write(socket, consumer, msg)
      socket.write(msg[:data])
    rescue StandardError => e
      consumer.send({ type: :error, message: "Write failed: #{e.message}" }.freeze)
    end

    def self.close_socket(socket)
      socket.close
    rescue StandardError
      nil
    end

    RACTOR_LOGIC = proc do
      loop do
        message = Ractor.receive
        next unless message[:type] == :connect

        h = message[:host]
        p = message[:port]
        consumer = message[:consumer]
        socket = nil
        reader_thread = nil

        begin
          socket = TCPSocket.new(h, p)
          socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
          consumer.send({ type: :connected, host: h, port: p }.freeze)

          reader_thread = Thread.new { SocketReaderRactor.reader_loop(socket, consumer) }
          SocketReaderRactor.writer_loop(socket, consumer, reader_thread)
          break
        rescue StandardError => e
          consumer.send({ type: :error, message: "Connection failed: #{e.message}" }.freeze)
        ensure
          reader_thread&.kill
          SocketReaderRactor.close_socket(socket) if socket
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
      { type: :timeout, message: 'Timed out waiting for message' }
    end

    def stop
      @pipe.send({ type: :stop }.freeze)
    end
  end
end
