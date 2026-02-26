require 'socket'
require 'thread'

module MockAMIServer
  def self.start(port = 0, &block)
    server = TCPServer.new('localhost', port)
    assigned_port = server.addr[1]
    
    # Store client threads to kill them later
    client_threads = []
    
    server_thread = Thread.new do
      begin
        loop do
          client = server.accept
          puts "Client connected: #{client.peeraddr.inspect}"
          
          t = Thread.new(client) do |c|
            begin
              c.puts "Asterisk Call Manager/1.1"
              
              if block_given?
                block.call(c)
              else
                while line = c.gets
                  c.puts "Echo: #{line}"
                end
              end
            rescue StandardError => e
              puts "Client error: #{e.message}"
            ensure
              c.close rescue nil
              puts "Client disconnected"
            end
          end
          client_threads << t
        end
      rescue IOError, Errno::EBADF
        # Server closed
      ensure
        server.close rescue nil
        client_threads.each(&:kill)
      end
    end
    
    [server_thread, assigned_port]
  end
end
