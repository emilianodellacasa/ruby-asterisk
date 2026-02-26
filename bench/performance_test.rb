# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('../spec', __dir__))

require 'ruby-asterisk'
require 'support/mock_ami_server'
require 'benchmark'
require 'timeout'

$stdout.sync = true

puts "Starting Benchmark for ruby-asterisk SocketReaderRactor..."

# Scenario 1: Throughput (Ping)
puts "\n--- Scenario 1: Throughput (1000 Pings) ---"

mock_server_thread, mock_port = MockAMIServer.start do |client|
  buffer = +""
  while line = client.gets
    # puts "S: #{line.inspect}"
    buffer << line
    if line == "\r\n" || line == "\n"
      # Process complete command
      if buffer =~ /ActionID: (.*?)\s/
        action_id = $1
        if buffer =~ /Action: Ping/
           client.print "Response: Success\r\nActionID: #{action_id}\r\nPing: Pong\r\n\r\n"
        elsif buffer =~ /Action: Login/
           client.print "Response: Success\r\nActionID: #{action_id}\r\nMessage: Authentication accepted\r\n\r\n"
        end
      end
      buffer.clear
    end
  end
end

begin
  client = RubyAsterisk::AMI::Client.new(host: 'localhost', port: mock_port)
  
  unless client.connect
    puts "Failed to connect!"
    exit 1
  end
  
  # Warmup
  client.ping
  
  n = 1000
  time = Benchmark.realtime do
    n.times do |i|
      resp = client.ping
      unless resp
        puts "Ping #{i} failed!"
        break
      end
      print "." if i % 100 == 0
    end
  end
  puts ""
  
  puts "Total Time: #{time.round(4)}s"
  puts "Throughput: #{(n / time).round(2)} req/s"
  puts "Avg Latency: #{(time / n * 1000).round(2)}ms"
  
  client.disconnect
ensure
  mock_server_thread.kill if mock_server_thread
end


# Scenario 2: Async Event Flood
puts "\n--- Scenario 2: Async Event Flood (5000 events) ---"

mock_server_thread, mock_port = MockAMIServer.start do |client|
  # Thread to blast events
  t_events = Thread.new do
    5000.times do |i|
      client.print "Event: TestEvent\r\nPrivilege: call,all\r\nSequenceNumber: #{i}\r\nFile: test.c\r\nLine: 123\r\nFunc: test_func\r\n\r\n"
      # sleep 0.0001 # Removed sleep to stress test harder
    end
  end
  
  # Handle Pings normally
  buffer = +""
  while line = client.gets
    buffer << line
    if line == "\r\n" || line == "\n"
      # Process complete command
      if buffer =~ /ActionID: (.*?)\s/
        action_id = $1
        if buffer =~ /Action: Ping/
           client.print "Response: Success\r\nActionID: #{action_id}\r\nPing: Pong\r\n\r\n"
        elsif buffer =~ /Action: Login/
           client.print "Response: Success\r\nActionID: #{action_id}\r\nMessage: Authentication accepted\r\n\r\n"
        end
      end
      buffer.clear
    end
  end
  t_events.join
end

begin
  client = RubyAsterisk::AMI::Client.new(host: 'localhost', port: mock_port)
  client.connect
  
  # Send pings while events are flooding
  n = 50
  success_count = 0
  
  time = Benchmark.realtime do
    n.times do |i|
      if client.ping
        success_count += 1
      end
      print "." if i % 10 == 0
    end
  end
  puts ""
  
  puts "Processed #{success_count}/#{n} Pings during flood"
  puts "Time: #{time.round(4)}s"
  puts "Throughput with flood: #{(n / time).round(2)} req/s"
  
  client.disconnect
ensure
  mock_server_thread.kill if mock_server_thread
end

puts "\nBenchmark Complete."
