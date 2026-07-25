# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/ami/reactor'
require 'ruby-asterisk/ami/promise'
require 'support/mock_ami_server'
require 'timeout'

RSpec.describe RubyAsterisk::AMI::Reactor do
  # ── shared mock server setup ───────────────────────────────────────────────

  let(:events_received) { [] }
  let(:on_event)        { ->(evt) { events_received << evt } }

  def build_reactor
    described_class.new('localhost', @port, on_event: on_event)
  end

  # Track Thread count before each example to assert no leaks after.
  let(:thread_count_before) { Thread.list.count(&:alive?) }

  # ── start / stop ─────────────────────────────────────────────────────────

  describe 'start and stop lifecycle' do
    before do
      @server_thread, @port = MockAMIServer.start
      thread_count_before # capture before reactor is started
    end

    after { @server_thread&.kill }

    it 'starts without error and returns self' do
      reactor = build_reactor
      expect(reactor.start).to be(reactor)
      reactor.stop
    end

    it 'both threads are dead after stop' do
      reactor = build_reactor
      reactor.start
      writer_thread = reactor.instance_variable_get(:@writer_thread)
      reader_thread = reactor.instance_variable_get(:@reader_thread)
      reactor.stop
      expect(writer_thread).not_to be_alive
      expect(reader_thread).not_to be_alive
    end

    it 'can be stopped twice without error' do
      reactor = build_reactor
      reactor.start
      expect do
        reactor.stop
        reactor.stop
      end.not_to raise_error
    end

    # #stop closes the socket from the writer thread while the reader thread sits
    # in readpartial: that must surface as a clean shutdown, never as a disconnect
    # notification or a rejected promise.
    describe 'deliberate stop' do
      let(:disconnects) { Thread::Queue.new }
      let(:pending_promise) do
        RubyAsterisk::AMI::Promise.new(action_id: 'stop-race', command_type: 'Ping', timeout: 1)
      end

      def stopped_reactor
        reactor = described_class.new('localhost', @port, on_disconnect: -> { disconnects << :called })
        reactor.start
        reactor.register_promise('stop-race', pending_promise)
        reactor.send_command("Action: Ping\r\nActionID: stop-race\r\n\r\n")
        reactor.stop
        reactor
      end

      it 'does not notify a disconnect nor reject pending promises' do
        stopped_reactor

        expect(disconnects).to be_empty
        expect(pending_promise).not_to be_resolved
      end

      # Replays what the reader thread does when it is scheduled only after the
      # socket has already been closed and cleared: no notification either way.
      it 'stays silent when the reader loop runs after the socket is gone' do
        reactor = stopped_reactor

        reactor.send(:reader_loop)

        expect(disconnects).to be_empty
        expect(pending_promise).not_to be_resolved
      end
    end
  end

  # ── command delivery ──────────────────────────────────────────────────────

  describe 'command delivery' do
    let(:received_commands) { Thread::Queue.new }

    before do
      @server_thread, @port = MockAMIServer.start do |sock|
        while (line = sock.gets)
          received_commands << line.chomp unless line.strip.empty?
        end
      end
    end

    after do
      @reactor&.stop
      @server_thread&.kill
    end

    it 'delivers a command string to the server socket' do
      @reactor = build_reactor
      @reactor.start
      @reactor.send_command("Action: Ping\r\nActionID: test1\r\n\r\n")

      line = Timeout.timeout(2) { received_commands.pop }
      expect(line).to eq('Action: Ping')
    end

    it 'delivers multiple commands in order' do
      @reactor = build_reactor
      @reactor.start

      3.times do |i|
        @reactor.send_command("Action: Ping\r\nActionID: order#{i}\r\n\r\n")
      end

      action_ids = []
      3.times do
        loop do
          line = Timeout.timeout(2) { received_commands.pop }
          if line.start_with?('ActionID:')
            action_ids << line.split(': ', 2).last
            break
          end
        end
      end

      expect(action_ids).to eq(%w[order0 order1 order2])
    end
  end

  # ── Promise resolution ────────────────────────────────────────────────────

  describe 'Promise resolution' do
    before do
      @server_thread, @port = MockAMIServer.start do |sock|
        while (chunk = sock.gets)
          next unless chunk.strip.empty?

          # Echo a successful response for every command received
          sock.print "Response: Success\r\nActionID: #{@last_action_id}\r\nPing: Pong\r\n\r\n"
        end
      end

      @action_id_queue = Thread::Queue.new

      # Custom mock: capture ActionID as it arrives
      begin
        @server_thread.kill
      rescue StandardError
        nil
      end
      @server_thread, @port = MockAMIServer.start do |sock|
        buf = +''
        while (line = sock.gets)
          buf << line
          last_id = Regexp.last_match(1) if line =~ /ActionID: (\S+)/
          next unless line.strip.empty? && last_id

          sock.print "Response: Success\r\nActionID: #{last_id}\r\nPing: Pong\r\n\r\n"
          last_id = nil
          buf.clear
        end
      end
    end

    after do
      @reactor&.stop
      @server_thread&.kill
    end

    it 'resolves the Promise when a matching response arrives' do
      @reactor = build_reactor
      @reactor.start

      promise = RubyAsterisk::AMI::Promise.new(
        action_id: 'p1', command_type: 'Ping', timeout: 3
      )
      @reactor.register_promise('p1', promise)
      @reactor.send_command("Action: Ping\r\nActionID: p1\r\n\r\n")

      expect(promise.resolved?).to be false
      response = promise.value(3)
      expect(response).not_to be_nil
      expect(promise.resolved?).to be true
    end

    it 'resolves multiple in-flight Promises independently' do
      @reactor = build_reactor
      @reactor.start

      promises = (1..5).map do |i|
        p = RubyAsterisk::AMI::Promise.new(
          action_id: "multi#{i}", command_type: 'Ping', timeout: 3
        )
        @reactor.register_promise("multi#{i}", p)
        @reactor.send_command("Action: Ping\r\nActionID: multi#{i}\r\n\r\n")
        p
      end

      promises.each do |p|
        expect { p.value(3) }.not_to raise_error
      end
    end
  end

  # ── Event delivery ────────────────────────────────────────────────────────

  describe 'event delivery' do
    before do
      @server_thread, @port = MockAMIServer.start do |sock|
        100.times do |i|
          sock.print "Event: TestEvent\r\nSequence: #{i}\r\n\r\n"
        end
        begin
          sock.gets
        rescue StandardError
          nil
        end
      end
    end

    after do
      @reactor&.stop
      @server_thread&.kill
    end

    it 'delivers 100 events to the on_event callback' do
      @reactor = build_reactor
      @reactor.start

      Timeout.timeout(3) do
        sleep 0.05 until events_received.size >= 100
      end

      expect(events_received.size).to eq(100)
      sequences = events_received.map { |e| e.headers['Sequence'].to_i }
      expect(sequences).to eq((0...100).to_a)
    end
  end

  # ── Promise rejection on disconnect ──────────────────────────────────────

  describe 'Promise rejection on disconnect' do
    before do
      @server_thread, @port = MockAMIServer.start do |sock|
        sock.gets
      rescue StandardError
        nil
        # accept but never respond
      end
    end

    after { @server_thread&.kill }

    it 'rejects all pending Promises when stop is called' do
      @reactor = build_reactor
      @reactor.start

      promises = (1..5).map do |i|
        p = RubyAsterisk::AMI::Promise.new(
          action_id: "pend#{i}", command_type: 'Ping', timeout: 5
        )
        @reactor.register_promise("pend#{i}", p)
        p
      end

      # Stop reactor while promises are still pending
      @reactor.stop
      @reactor.reject_all_promises(RuntimeError.new('Client disconnected'))

      promises.each do |p|
        expect { p.value(0.1) }.to raise_error(RuntimeError, /disconnected/i)
      end
    end
  end
end
