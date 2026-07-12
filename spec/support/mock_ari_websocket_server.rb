# frozen_string_literal: true

require 'socket'
require 'json'
require 'websocket/driver'

# Minimal in-process WebSocket server used by ARI::WebSocket integration specs.
# Accepts connections on an ephemeral port, completes the WebSocket handshake
# with websocket-driver in server mode, and records what clients send.
class MockAriWebSocketServer
  # websocket-driver server adapter: it only needs #write
  class ServerAdapter
    def initialize(io)
      @io = io
    end

    def write(data)
      @io.write(data)
    end
  end

  ClientConnection = Struct.new(:socket, :driver)

  attr_reader :port, :messages, :pings, :connections

  def initialize
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @messages = Queue.new    # text frames received from clients
    @pings = Queue.new       # ping frames received from clients
    @connections = Queue.new # one entry per completed handshake
    @clients = []
    @clients_mutex = Mutex.new
    @accept_thread = Thread.new { accept_loop }
  end

  # Send an event (Hash) to every connected client
  def broadcast(event)
    data = JSON.generate(event)
    each_client { |client| client.driver.text(data) }
  end

  # Close every client socket abruptly (no close frame), simulating a drop
  def drop_clients
    each_client { |client| client.socket.close }
    @clients_mutex.synchronize { @clients.clear }
  end

  def stop
    @server.close
    @accept_thread.join(1)
    drop_clients
  rescue IOError
    nil
  end

  # Pop from one of the queues, failing the spec on timeout
  def self.pop(queue, timeout = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return queue.pop(true)
    rescue ThreadError
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "timed out waiting for queue after #{timeout}s"
      end

      sleep 0.01
    end
  end

  private

  def accept_loop
    loop do
      socket = @server.accept
      Thread.new { handle_client(socket) }
    end
  rescue IOError, SystemCallError
    nil
  end

  def handle_client(socket)
    driver = ::WebSocket::Driver.server(ServerAdapter.new(socket))
    client = ClientConnection.new(socket, driver)
    @clients_mutex.synchronize { @clients << client }

    setup_driver(driver, client)
    driver.parse(socket.readpartial(4096)) until socket.closed?
  rescue IOError, SystemCallError
    nil
  ensure
    begin
      socket.close
    rescue StandardError
      nil
    end
  end

  def setup_driver(driver, client)
    driver.on(:connect) { driver.start if ::WebSocket::Driver.websocket?(driver.env) }
    driver.on(:open) { @connections << client }
    driver.on(:message) { |event| @messages << event.data }
    driver.on(:ping) { |event| @pings << event }
  end

  def each_client
    clients = @clients_mutex.synchronize { @clients.dup }
    clients.each do |client|
      yield client
    rescue IOError, SystemCallError
      nil
    end
  end
end
