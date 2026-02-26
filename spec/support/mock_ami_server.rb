# frozen_string_literal: true

require 'socket'

module MockAMIServer
  def self.handle_client(client, &block)
    client.puts 'Asterisk Call Manager/1.1'

    if block
      yield(client)
    else
      while (line = client.gets)
        client.puts "Echo: #{line}"
      end
    end
  rescue StandardError => e
    puts "Client error: #{e.message}"
  ensure
    begin
      client.close
    rescue StandardError
      nil
    end
    puts 'Client disconnected'
  end

  def self.start(port = 0, &block)
    server = TCPServer.new('localhost', port)
    assigned_port = server.addr[1]

    client_threads = []
    server_thread = Thread.new do
      loop do
        client = server.accept
        puts "Client connected: #{client.peeraddr.inspect}"
        client_threads << Thread.new(client) { |c| handle_client(c, &block) }
      end
    rescue IOError, Errno::EBADF # Server closed
    ensure
      begin
        server.close
      rescue StandardError
        nil
      end
      client_threads.each(&:kill)
    end

    [server_thread, assigned_port]
  end
end
