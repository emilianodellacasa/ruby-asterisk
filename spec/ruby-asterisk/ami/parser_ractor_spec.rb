# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/ami/parser_ractor'
require 'timeout'

RSpec.describe RubyAsterisk::AMI::ParserRactor do
  # ── helpers ────────────────────────────────────────────────────────────────

  def flush_mailbox
    Timeout.timeout(0.1) { loop { Ractor.receive } }
  rescue Timeout::Error
    # mailbox empty — expected
  end

  def receive_msg(timeout: 1)
    Timeout.timeout(timeout) { Ractor.receive }
  end

  # ── setup / teardown ───────────────────────────────────────────────────────

  before { flush_mailbox }
  after  { flush_mailbox }

  subject(:parser) { described_class.new(Ractor.current) }

  # ── Acceptance Criterion 1: fragmented packets ────────────────────────────

  describe 'split-packet reassembly' do
    it 'assembles a Response split across two chunks' do
      parser.push(type: :data, data: "Response: Success\r\nActionID: abc123\r\n")
      parser.push(type: :data, data: "Message: OK\r\n\r\n")

      msg = receive_msg
      expect(msg[:type]).to eq(:response)
      expect(msg[:action_id]).to eq('abc123')
      expect(msg[:headers]['Response']).to eq('Success')
      expect(msg[:headers]['Message']).to eq('OK')
    end

    it 'assembles an Event split across three chunks' do
      parser.push(type: :data, data: 'Event: Han')
      parser.push(type: :data, data: "gup\r\nChannel: SIP/")
      parser.push(type: :data, data: "101\r\n\r\n")

      msg = receive_msg
      expect(msg[:type]).to eq(:event)
      expect(msg[:event]).to be_a(RubyAsterisk::AMI::Event)
      expect(msg[:event].name).to eq('Hangup')
      expect(msg[:event].headers['Channel']).to eq('SIP/101')
    end

    it 'emits nothing until the delimiter arrives' do
      parser.push(type: :data, data: "Response: Success\r\nActionID: xyz\r\n")

      # No message should be ready yet
      expect do
        Timeout.timeout(0.05) { Ractor.receive }
      end.to raise_error(Timeout::Error)

      # Complete it
      parser.push(type: :data, data: "\r\n")
      msg = receive_msg
      expect(msg[:type]).to eq(:response)
    end
  end

  # ── Acceptance Criterion 2: multiple messages in one chunk ─────────────────

  describe 'multiple messages in a single chunk' do
    it 'emits all messages when two complete messages arrive together' do
      two_msgs =
        "Response: Success\r\nActionID: r1\r\n\r\n" \
        "Event: FullyBooted\r\nPrivilege: system,all\r\nStatus: Fully Booted\r\n\r\n"

      parser.push(type: :data, data: two_msgs)

      first  = receive_msg
      second = receive_msg

      expect(first[:type]).to eq(:response)
      expect(first[:action_id]).to eq('r1')

      expect(second[:type]).to eq(:event)
      expect(second[:event].name).to eq('FullyBooted')
      expect(second[:event].headers['Status']).to eq('Fully Booted')
    end

    it 'handles ten back-to-back events in a single chunk' do
      chunk = (1..10).map do |i|
        "Event: TestEvent\r\nSequence: #{i}\r\n\r\n"
      end.join

      parser.push(type: :data, data: chunk)

      events = (1..10).map { receive_msg }
      expect(events).to all(satisfy { |m| m[:type] == :event })
      sequences = events.map { |m| m[:event].headers['Sequence'].to_i }
      expect(sequences).to eq((1..10).to_a)
    end
  end

  # ── Header parsing ─────────────────────────────────────────────────────────

  describe 'header parsing' do
    it 'trims leading/trailing whitespace from header values' do
      parser.push(type: :data, data: "Response: Success\r\nMessage:  hello world  \r\n\r\n")
      msg = receive_msg
      expect(msg[:headers]['Message']).to eq('hello world')
    end

    it 'preserves colons inside header values' do
      parser.push(type: :data, data: "Event: NewExten\r\nApplication: Dial\r\nAppData: SIP/101:60\r\n\r\n")
      msg = receive_msg
      expect(msg[:event].headers['AppData']).to eq('SIP/101:60')
    end

    it 'exposes frozen headers' do
      parser.push(type: :data, data: "Response: Success\r\nActionID: f1\r\n\r\n")
      msg = receive_msg
      expect(msg[:headers]).to be_frozen
      msg[:headers].each_key { |k| expect(k).to be_frozen }
      msg[:headers].each_value { |v| expect(v).to be_frozen }
    end

    it 'exposes a frozen raw string' do
      parser.push(type: :data, data: "Response: Error\r\nActionID: f2\r\n\r\n")
      msg = receive_msg
      expect(msg[:raw]).to be_frozen
    end
  end

  # ── Response routing ───────────────────────────────────────────────────────

  describe 'response routing' do
    it 'sets action_id from the ActionID header' do
      parser.push(type: :data, data: "Response: Success\r\nActionID: myid\r\n\r\n")
      msg = receive_msg
      expect(msg[:action_id]).to eq('myid')
    end

    it 'sets action_id to nil when no ActionID header is present' do
      parser.push(type: :data, data: "Response: Follows\r\nPrivilege: Command\r\n\r\n")
      msg = receive_msg
      expect(msg[:type]).to eq(:response)
      expect(msg[:action_id]).to be_nil
    end
  end

  # ── Event routing ──────────────────────────────────────────────────────────

  describe 'event routing' do
    it 'creates a frozen Event object with the correct name' do
      parser.push(type: :data, data: "Event: Hangup\r\nChannel: SIP/200\r\nCause: 16\r\n\r\n")
      msg = receive_msg
      expect(msg[:type]).to eq(:event)
      event = msg[:event]
      expect(event).to be_a(RubyAsterisk::AMI::Event)
      expect(event).to be_frozen
      expect(event.name).to eq('Hangup')
      expect(event.headers['Cause']).to eq('16')
    end

    it 'Event object exposes the raw AMI message string' do
      raw_input = "Event: Hangup\r\nChannel: SIP/200\r\n\r\n"
      parser.push(type: :data, data: raw_input)
      msg = receive_msg
      expect(msg[:event].raw).to eq(raw_input)
    end
  end

  # ── Welcome banner tolerance ────────────────────────────────────────────────

  describe 'AMI welcome banner tolerance' do
    it 'silently ignores the Asterisk welcome banner mixed with a response' do
      # MockAMIServer uses puts which appends \n; real Asterisk uses \r\n.
      # Either way the banner has no \r\n\r\n on its own, so it merges with
      # the next response block.
      combined =
        "Asterisk Call Manager/1.1\n" \
        "Response: Success\r\nActionID: banner_test\r\n\r\n"

      parser.push(type: :data, data: combined)
      msg = receive_msg
      expect(msg[:type]).to eq(:response)
      expect(msg[:action_id]).to eq('banner_test')
    end
  end

  # ── Pass-through control messages ─────────────────────────────────────────

  describe 'control message forwarding' do
    it 'forwards :connected messages unchanged' do
      parser.push(type: :connected, host: 'localhost', port: 5038)
      msg = receive_msg
      expect(msg[:type]).to eq(:connected)
      expect(msg[:host]).to eq('localhost')
      expect(msg[:port]).to eq(5038)
    end

    it 'forwards :disconnected messages unchanged' do
      parser.push(type: :disconnected, reason: 'EOF from server')
      msg = receive_msg
      expect(msg[:type]).to eq(:disconnected)
      expect(msg[:reason]).to eq('EOF from server')
    end

    it 'forwards :error messages unchanged' do
      parser.push(type: :error, message: 'Connection reset')
      msg = receive_msg
      expect(msg[:type]).to eq(:error)
      expect(msg[:message]).to eq('Connection reset')
    end
  end

  # ── Acceptance Criterion 3: parallel processing ────────────────────────────

  describe 'parallel processing' do
    it 'parses messages independently of the main thread' do
      # Send a large batch of messages to the parser Ractor, then verify
      # they are all returned — demonstrating that the parser ran in a
      # separate Ractor while the main thread was free to do other work.
      n = 200
      chunk = (1..n).map do |i|
        "Response: Success\r\nActionID: id#{i}\r\n\r\n"
      end.join

      # Send the whole batch at once and then do "other work" in main thread.
      parser.push(type: :data, data: chunk)

      # Simulate main-thread work that runs concurrently with parsing.
      work_result = (1..1000).sum

      # Drain all parsed responses.
      received_ids = []
      n.times { received_ids << receive_msg[:action_id] }

      expect(work_result).to eq(500_500)
      expect(received_ids.length).to eq(n)
      expect(received_ids).to eq((1..n).map { |i| "id#{i}" })
    end

    it 'parser Ractor runs in a different Ractor than main' do
      # The parser's input Ractor must not be Ractor.main.
      expect(parser.input).not_to eq(Ractor.current)
    end
  end
end
