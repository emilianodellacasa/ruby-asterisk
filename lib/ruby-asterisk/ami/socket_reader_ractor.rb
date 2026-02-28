# frozen_string_literal: true

require 'socket'

module RubyAsterisk
  # Dedicated Ractor for reading from the Asterisk socket
  class SocketReaderRactor
    attr_reader :host, :port

    # Reads data from the socket and forwards chunks to the consumer.
    # Exits when the socket is closed or EOF is reached.
    def self.reader_loop(socket, consumer)
      loop do
        chunk = socket.readpartial(4096)
        consumer.send({ type: :data, data: chunk.freeze }.freeze)
      end
    rescue EOFError
      safe_send(consumer, { type: :disconnected, reason: 'EOF from server' }.freeze)
    rescue IOError, Errno::EBADF
      # Socket was closed from stop command — exit silently without notifying consumer
    rescue StandardError => e
      safe_send(consumer, { type: :error, message: e.message }.freeze)
    end

    # Handles write commands and stop signal from the main Ractor.
    # Closing the socket on :stop unblocks reader_loop's readpartial call.
    def self.writer_loop(socket, consumer, reader_thread)
      loop do
        msg = Ractor.receive
        case msg[:type]
        when :write
          handle_write(socket, consumer, msg)
        when :stop
          close_socket(socket)      # unblocks reader_loop's readpartial
          reader_thread&.join(2)    # wait for reader_loop to exit cleanly
          break
        end
      end
    end

    def self.handle_write(socket, consumer, msg)
      socket.write(msg[:data])
    rescue StandardError => e
      safe_send(consumer, { type: :error, message: "Write failed: #{e.message}" }.freeze)
    end

    def self.close_socket(socket)
      socket.close
    rescue StandardError
      nil
    end

    def self.safe_send(consumer, msg)
      consumer.send(msg)
    rescue StandardError
      nil
    end

    def self.connect_and_loop(host, port, consumer)
      socket = nil
      reader_thread = nil

      begin
        socket = TCPSocket.new(host, port)
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
        consumer.send({ type: :connected, host: host, port: port }.freeze)

        reader_thread = Thread.new { SocketReaderRactor.reader_loop(socket, consumer) }
        SocketReaderRactor.writer_loop(socket, consumer, reader_thread)
      rescue StandardError => e
        safe_send(consumer, { type: :error, message: "Connection failed: #{e.message}" }.freeze)
      ensure
        SocketReaderRactor.close_socket(socket) if socket
        reader_thread&.join(1)
      end
    end

    RACTOR_LOGIC = proc do
      loop do
        message = Ractor.receive
        next unless message[:type] == :connect

        SocketReaderRactor.connect_and_loop(message[:host], message[:port], message[:consumer])
        break
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
