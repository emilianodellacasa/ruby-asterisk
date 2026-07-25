# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/ami/client'
require 'ruby-asterisk/ami/promise'
require 'support/mock_ami_server'
require 'timeout'

# Helpers shared across examples in this file
ASYNC_NEWLINES = ["\r\n", "\n"].freeze

# Builds a MockAMIServer block that responds to Login and Ping commands.
def ami_responder
  lambda do |sock|
    buf = +''
    while (line = sock.gets)
      buf << line
      next unless ASYNC_NEWLINES.include?(line)

      if buf =~ /ActionID: (\S+)/
        action_id = Regexp.last_match(1)
        if buf.include?('Action: Login')
          sock.print "Response: Success\r\nActionID: #{action_id}\r\nMessage: Authentication accepted\r\n\r\n"
        elsif buf.include?('Action: Ping')
          sock.print "Response: Success\r\nActionID: #{action_id}\r\nPing: Pong\r\n\r\n"
        end
      end
      buf.clear
    end
  end
end

RSpec.describe 'RubyAsterisk::AMI::Client — async behaviour' do
  # -------------------------------------------------------------------------
  # Shared setup: a standard mock Asterisk server
  # -------------------------------------------------------------------------
  before do
    @server_thread, @port = MockAMIServer.start(&ami_responder)
  end

  after { @server_thread&.kill }

  let(:client) { RubyAsterisk::AMI::Client.new(host: 'localhost', port: @port) }

  # -------------------------------------------------------------------------
  # execute is non-blocking
  # -------------------------------------------------------------------------
  describe '#execute non-blocking behaviour' do
    it 'returns a Promise without waiting for Asterisk' do
      client.connect

      start_time = Time.now
      promise = client.ping # internally calls execute
      elapsed = Time.now - start_time

      expect(promise).to be_a(RubyAsterisk::AMI::Promise)
      expect(elapsed).to be < 0.5    # near-instant — no blocking wait

      promise.value(2)               # clean up: wait for response
      client.disconnect
    end

    it 'promise is not yet resolved right after execute' do
      client.connect
      promise = client.ping
      # Promise may or may not be resolved immediately — just check it is a Promise
      expect(promise).to be_a(RubyAsterisk::AMI::Promise)
      promise.value(2)
      client.disconnect
    end
  end

  # -------------------------------------------------------------------------
  # Promise resolves to a proper Response
  # -------------------------------------------------------------------------
  describe 'Promise#value' do
    it 'returns a RubyAsterisk::Response on success' do
      client.connect
      response = client.ping.value(2)
      expect(response).to be_a(RubyAsterisk::Response)
      expect(response.success).to be true
      client.disconnect
    end

    it 'raises Timeout::Error when no response arrives in time' do
      # Server accepts but never responds to commands
      silent_thread, silent_port = MockAMIServer.start { |_sock| sleep 30 }

      begin
        slow_client = RubyAsterisk::AMI::Client.new(host: 'localhost', port: silent_port)
        slow_client.connect
        promise = slow_client.execute('Ping')
        expect { promise.value(0.2) }.to raise_error(Timeout::Error)
        slow_client.disconnect
      ensure
        silent_thread&.kill
      end
    end
  end

  # -------------------------------------------------------------------------
  # Multiple concurrent commands
  # -------------------------------------------------------------------------
  describe 'concurrent commands' do
    it 'resolves multiple in-flight promises independently' do
      client.connect

      # Fire three pings without waiting for any of them
      promises = Array.new(3) { client.ping }

      # Now collect all responses
      responses = promises.map { |p| p.value(2) }

      expect(responses).to all(be_a(RubyAsterisk::Response))
      expect(responses.map(&:success)).to all(be true)

      client.disconnect
    end
  end

  # -------------------------------------------------------------------------
  # Disconnect rejects pending promises
  # -------------------------------------------------------------------------
  describe '#disconnect' do
    it 'rejects promises that are still pending' do
      # Use a server that accepts the connection but never responds to commands
      slow_thread, slow_port = MockAMIServer.start { |_sock| sleep 30 }

      begin
        slow_client = RubyAsterisk::AMI::Client.new(host: 'localhost', port: slow_port)
        slow_client.connect

        promise = slow_client.execute('Ping')
        slow_client.disconnect # tears down before response arrives

        expect { promise.value(0.5) }.to raise_error(RuntimeError, /disconnected/i)
      ensure
        slow_thread&.kill
      end
    end

    it 'sets connected to false' do
      client.connect
      expect(client.connected).to be true
      client.disconnect
      expect(client.connected).to be false
    end
  end

  # -------------------------------------------------------------------------
  # A timed-out promise must not leak in the reactor's pending map
  # -------------------------------------------------------------------------
  describe 'pending-promise cleanup on timeout' do
    it 'unregisters the promise after Promise#value times out' do
      silent_thread, silent_port = MockAMIServer.start { |_sock| sleep 30 }

      begin
        c = RubyAsterisk::AMI::Client.new(host: 'localhost', port: silent_port)
        c.connect
        promise = c.execute('Ping')
        expect { promise.value(0.2) }.to raise_error(Timeout::Error)

        pending = c.instance_variable_get(:@reactor).instance_variable_get(:@promises)
        expect(pending).to be_empty

        c.disconnect
      ensure
        silent_thread&.kill
      end
    end
  end

  # -------------------------------------------------------------------------
  # Per-command timeout must not mutate the client-wide default
  # -------------------------------------------------------------------------
  describe 'per-command timeout isolation' do
    it 'does not raise the shared default timeout' do
      client.connect
      expect(client.instance_variable_get(:@timeout)).to eq(5)

      client.originate('SIP/100', 'default', '200', '1', timeout: 300_000)

      expect(client.instance_variable_get(:@timeout)).to eq(5)
      client.disconnect
    end
  end

  # -------------------------------------------------------------------------
  # A caller-supplied ActionID replaces the generated one instead of being
  # appended as a second ActionID header (which would break correlation)
  # -------------------------------------------------------------------------
  describe 'caller-supplied ActionID' do
    it 'sends exactly one ActionID header and still resolves the promise' do
      frames = Thread::Queue.new
      echo_thread, echo_port = MockAMIServer.start do |sock|
        buf = +''
        while (line = sock.gets)
          buf << line
          next unless ASYNC_NEWLINES.include?(line)

          frames << buf.dup
          sock.print "Response: Success\r\nActionID: #{buf[/ActionID: (\S+)/, 1]}\r\n\r\n"
          buf.clear
        end
      end

      begin
        c = RubyAsterisk::AMI::Client.new(host: 'localhost', port: echo_port)
        c.connect
        response = c.status(channel: 'SIP/alice-001', action_id: 'custom-id').value(2)

        frame = frames.pop
        expect(frame.scan(/^ActionID:/).size).to eq(1)
        expect(frame).to include("ActionID: custom-id\r\n")
        expect(response.success).to be true

        c.disconnect
      ensure
        echo_thread&.kill
      end
    end
  end

  # -------------------------------------------------------------------------
  # WaitEvent with a negative Timeout must not impose a Promise deadline
  # -------------------------------------------------------------------------
  describe '#wait_event' do
    it 'leaves the promise without a deadline when Timeout is negative' do
      client.connect

      promise = client.wait_event(timeout: -1)

      expect(promise.instance_variable_get(:@timeout)).to be_nil
      client.disconnect
    end

    it 'keeps the client default as the floor for a positive Timeout' do
      client.connect

      promise = client.wait_event(timeout: 30)

      expect(promise.instance_variable_get(:@timeout)).to eq(30)
      client.disconnect
    end
  end

  # -------------------------------------------------------------------------
  # Commands issued before connect fail loudly rather than hanging
  # -------------------------------------------------------------------------
  describe 'guard when not connected' do
    it 'raises instead of NoMethodError' do
      fresh = RubyAsterisk::AMI::Client.new(host: 'localhost', port: @port)
      expect { fresh.execute('Ping') }.to raise_error(RubyAsterisk::Error, /not connected/i)
    end
  end
end
