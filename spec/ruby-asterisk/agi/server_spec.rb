# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/agi/server'
require 'socket'
require 'timeout'

# Starts an AGI server on an ephemeral port and returns [server, server_thread, port].
# Automatically registers an after hook that calls stop and joins the thread.
def start_test_server(server, &)
  server.handle(&)
  thread = Thread.new { server.run }
  Timeout.timeout(2) { sleep 0.01 until server.running? || !thread.alive? }
  raise 'Server did not start' unless server.running?

  [thread, server.port]
end

# Connect as a fake Asterisk client, send env + responses, collect written commands.
def fake_asterisk_session(port, env_lines: [], responses: [])
  socket = TCPSocket.new('127.0.0.1', port)
  # Send env block
  env_lines.each { |l| socket.puts(l) }
  socket.puts('') # blank line terminates env

  received_commands = []
  responses.each do |resp|
    cmd = socket.gets
    received_commands << cmd.chomp if cmd
    socket.puts(resp)
  end

  socket.close
  received_commands
rescue StandardError => e
  socket&.close
  raise e
end

RSpec.describe RubyAsterisk::AGI::Server do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }
  subject(:server) { described_class.new('127.0.0.1', 0, logger: logger) }

  after do
    server.stop if server.running?
  end

  describe '#initialize' do
    it 'stores the host' do
      expect(server.host).to eq('127.0.0.1')
    end

    it 'starts with running? false' do
      expect(server.running?).to be(false)
    end
  end

  describe '#handle' do
    it 'stores the handler and returns self' do
      result = server.handle { |s| s }
      expect(result).to be(server)
    end
  end

  describe '#run' do
    it 'raises RubyAsterisk::Error when no handler is registered' do
      expect { server.run }.to raise_error(RubyAsterisk::Error, /No handler registered/)
    end

    it 'blocks and sets running? to true while accepting' do
      _thread, _port = start_test_server(server) { |_s| nil }
      expect(server.running?).to be(true)
    end

    it 'sets running? back to false after stop' do
      thread, = start_test_server(server) { |_s| nil }
      server.stop
      thread.join(2)
      expect(server.running?).to be(false)
    end

    it 'updates port to the actual bound port when given 0' do
      start_test_server(server) { |_s| nil }
      expect(server.port).to be > 0
    end
  end

  describe 'connection handling' do
    it 'invokes the handler with a Session for each connection' do
      sessions_seen = []
      _thread, port = start_test_server(server) do |session|
        sessions_seen << session
      end

      fake_asterisk_session(port, env_lines: ['agi_channel: SIP/test'])
      sleep 0.1
      server.stop

      expect(sessions_seen.length).to eq(1)
      expect(sessions_seen.first).to be_a(RubyAsterisk::AGI::Session)
    end

    it 'populates session.env from the AGI environment block' do
      captured_env = nil
      _thread, port = start_test_server(server) do |session|
        captured_env = session.env.dup
      end

      fake_asterisk_session(port, env_lines: ['agi_channel: SIP/alice', 'agi_callerid: 5551234'])
      sleep 0.1
      server.stop

      expect(captured_env['agi_channel']).to eq('SIP/alice')
      expect(captured_env['agi_callerid']).to eq('5551234')
    end

    it 'exchanges AGI commands and responses correctly' do
      _thread, port = start_test_server(server) do |session|
        session.answer
        session.hangup
      end

      cmds = fake_asterisk_session(port,
                                   env_lines: ['agi_channel: SIP/test'],
                                   responses: ['200 result=1', '200 result=1'])
      server.stop

      expect(cmds).to eq(%w[ANSWER HANGUP])
    end

    it 'does not crash the accept loop when a handler raises' do
      call_count = 0
      _thread, port = start_test_server(server) do |_session|
        call_count += 1
        raise 'deliberate error' if call_count == 1
      end

      fake_asterisk_session(port, env_lines: [])
      sleep 0.05
      fake_asterisk_session(port, env_lines: [])
      sleep 0.05
      server.stop

      expect(call_count).to eq(2)
      expect(logger).to have_received(:error).at_least(:once)
    end
  end

  describe 'concurrency' do
    it 'handles multiple simultaneous connections using Fiber scheduling' do
      guard            = Mutex.new
      started          = 0
      finished         = 0
      captured_scheduler = nil

      _thread, port = start_test_server(server) do |_session|
        guard.synchronize do
          started += 1
          captured_scheduler ||= Fiber.scheduler
        end
        sleep 0.2
        guard.synchronize { finished += 1 }
      end

      start = Time.now

      Array.new(5) do
        Thread.new do
          fake_asterisk_session(port, env_lines: [])
        rescue StandardError
          nil
        end
      end.each(&:join)

      # Wait until all 5 handlers have started.
      Timeout.timeout(2) { sleep 0.01 until started == 5 }

      server.stop

      # With Fiber scheduling all 5 handlers run concurrently, so finishing
      # takes ~0.2s regardless of connection count.
      Timeout.timeout(2) { sleep 0.01 until finished == 5 }
      elapsed = Time.now - start

      expect(finished).to eq(5)
      expect(elapsed).to be < 0.8
      # Proves handlers ran inside an Async Fiber scheduler, not threads.
      expect(captured_scheduler).not_to be_nil
    end
  end

  describe '#stop' do
    it 'is idempotent — calling twice does not raise' do
      start_test_server(server) { |_s| nil }
      server.stop
      expect { server.stop }.not_to raise_error
    end
  end
end
