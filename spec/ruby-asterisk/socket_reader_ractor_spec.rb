# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/ami/socket_reader_ractor'
require 'support/mock_ami_server'

RSpec.describe RubyAsterisk::SocketReaderRactor do
  let(:mock_server_thread) { nil }
  let(:mock_port) { 0 }

  # Use a proxy Ractor to consume messages and push to a shared Queue.
  # This works because Ractor CAN share frozen messages.
  # And Ractor CAN send to a Queue IF the queue is shared? No.
  # Ractor CAN yield messages.
  # But we need to pipe from Ractor -> Queue in main thread.

  # Design:
  # Main thread creates a Ractor: "ConsumerProxy"
  # ConsumerProxy receives messages from SocketReaderRactor.
  # ConsumerProxy yields them back to Main thread? No, that's synchronous.
  # ConsumerProxy pushes to a Queue? Ractor cannot push to standard Queue unless...
  # Wait, Ractor CAN push to Ractor::Queue? No such thing.

  # Let's keep it simple: Use a new Ractor as consumer, and use Ractor#take to read from it.
  # The consumer Ractor will just be a buffer?
  # Or... just use a new Ractor for EACH test as the "listener".
  # And that listener Ractor yields messages to the test runner via take?

  # Yes!
  # consumer = Ractor.new { loop { Ractor.yield(Ractor.receive) } }
  # reader.start(consumer: consumer)
  # msg = consumer.take

  # But wait! Ractor#take is GONE!
  # So I cannot use consumer.take.

  # I MUST use Ractor.current as consumer.
  # BUT I need to flush the mailbox between tests!

  # How to flush Ractor mailbox?
  # Ractor.receive_if { true } until empty?
  # But receive blocks if empty.
  # Timeout.timeout(0.1) { loop { Ractor.receive } } rescue nil

  # Let's add a `flush_mailbox` helper in `before` block.

  def flush_mailbox
    Timeout.timeout(0.1) do
      loop do
        Ractor.receive
      end
    end
  rescue Timeout::Error
    # Mailbox empty
  end

  before do
    flush_mailbox
    # Start mock server
    @server_thread, @port = MockAMIServer.start
  end

  after do
    begin
      @reader&.stop
    rescue StandardError
      nil
    end
    @server_thread&.kill
    flush_mailbox
  end

  describe '#start' do
    it 'connects to the server' do
      @reader = described_class.new('localhost', @port)
      @reader.start # uses Ractor.current

      # Expect connected message
      msg = @reader.take # uses Ractor.receive
      expect(msg[:type]).to eq(:connected)
      expect(msg[:host]).to eq('localhost')
      expect(msg[:port]).to eq(@port)
    end
  end

  describe '#read_loop' do
    it 'reads data chunks' do
      @reader = described_class.new('localhost', @port)
      @reader.start

      # Get welcome message (AMI server default behavior)
      msg = @reader.take # :connected
      expect(msg[:type]).to eq(:connected)

      # Wait for data (Mock server sends "Asterisk Call Manager/1.1")
      msg = @reader.take
      expect(msg[:type]).to eq(:data)
      expect(msg[:data]).to match(/Asterisk Call Manager/)
    end

    it 'handles EOF gracefully' do
      @reader = described_class.new('localhost', @port)
      @reader.start

      msg = @reader.take
      expect(msg[:type]).to eq(:connected)

      # Consume data until we are sure server is idle or we kill it
      # Consume at least one data packet (welcome)
      msg = @reader.take
      expect(msg[:type]).to eq(:data)

      # Server disconnects
      @server_thread.kill

      # We need to wait for the socket close to propagate
      loop do
        msg = @reader.take
        break if msg[:type] == :disconnected
        # If we get :timeout, loop will raise Timeout::Error or check type
        raise 'Timeout waiting for disconnected' if msg[:type] == :timeout
      end

      expect(msg[:type]).to eq(:disconnected)
    end
  end
end
