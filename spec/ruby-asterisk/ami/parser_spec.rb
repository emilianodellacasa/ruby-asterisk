# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/ami/parser'

RSpec.describe RubyAsterisk::AMI::Parser do
  # Helper: push chunks into a buffer, drain, collect yielded messages.
  def drain_chunks(*chunks)
    buffer = +''
    msgs   = []
    chunks.each do |chunk|
      buffer << chunk
      described_class.drain(buffer) { |m| msgs << m }
    end
    msgs
  end

  # ── parse_headers ───────────────────────────────────────────────────────────

  describe '.parse_headers' do
    it 'parses key-value lines' do
      raw = "Response: Success\r\nActionID: abc\r\nMessage: OK\r\n"
      h = described_class.parse_headers(raw)
      expect(h['Response']).to eq('Success')
      expect(h['ActionID']).to eq('abc')
      expect(h['Message']).to eq('OK')
    end

    it 'trims leading/trailing whitespace from values' do
      h = described_class.parse_headers("Response: Success\r\nMessage:  hello world  \r\n")
      expect(h['Message']).to eq('hello world')
    end

    it 'preserves colons inside values' do
      h = described_class.parse_headers("Event: NewExten\r\nAppData: SIP/101:60\r\n")
      expect(h['AppData']).to eq('SIP/101:60')
    end

    it 'skips lines without a colon separator (e.g. AMI welcome banner)' do
      h = described_class.parse_headers("Asterisk Call Manager/1.1\nResponse: Success\r\n")
      expect(h.keys).to eq(['Response'])
    end

    it 'returns a frozen hash with frozen keys and values' do
      h = described_class.parse_headers("Response: OK\r\nActionID: x\r\n")
      expect(h).to be_frozen
      h.each_key   { |k| expect(k).to be_frozen }
      h.each_value { |v| expect(v).to be_frozen }
    end
  end

  # ── drain / split-packet reassembly ─────────────────────────────────────────

  describe '.drain — split-packet reassembly' do
    it 'assembles a Response split across two chunks' do
      msgs = drain_chunks(
        "Response: Success\r\nActionID: abc123\r\n",
        "Message: OK\r\n\r\n"
      )
      expect(msgs.size).to eq(1)
      expect(msgs.first[:type]).to eq(:response)
      expect(msgs.first[:action_id]).to eq('abc123')
      expect(msgs.first[:headers]['Message']).to eq('OK')
    end

    it 'assembles an Event split across three chunks' do
      msgs = drain_chunks(
        'Event: Han',
        "gup\r\nChannel: SIP/",
        "101\r\n\r\n"
      )
      expect(msgs.size).to eq(1)
      expect(msgs.first[:type]).to eq(:event)
      expect(msgs.first[:event].name).to eq('Hangup')
      expect(msgs.first[:event].headers['Channel']).to eq('SIP/101')
    end

    it 'emits nothing until the delimiter arrives' do
      msgs = drain_chunks("Response: Success\r\nActionID: xyz\r\n")
      expect(msgs).to be_empty
    end

    it 'emits the message once the delimiter arrives' do
      msgs = drain_chunks(
        "Response: Success\r\nActionID: xyz\r\n",
        "\r\n"
      )
      expect(msgs.size).to eq(1)
    end
  end

  # ── multiple messages in one chunk ─────────────────────────────────────────

  describe '.drain — multiple messages in one chunk' do
    it 'emits all messages when two complete messages arrive together' do
      two_msgs =
        "Response: Success\r\nActionID: r1\r\n\r\n" \
        "Event: FullyBooted\r\nPrivilege: system,all\r\nStatus: Fully Booted\r\n\r\n"

      msgs = drain_chunks(two_msgs)
      expect(msgs.size).to eq(2)
      expect(msgs[0][:type]).to eq(:response)
      expect(msgs[0][:action_id]).to eq('r1')
      expect(msgs[1][:type]).to eq(:event)
      expect(msgs[1][:event].name).to eq('FullyBooted')
    end

    it 'handles ten back-to-back events in a single chunk' do
      chunk = (1..10).map { |i| "Event: TestEvent\r\nSequence: #{i}\r\n\r\n" }.join
      msgs  = drain_chunks(chunk)
      expect(msgs.size).to eq(10)
      sequences = msgs.map { |m| m[:event].headers['Sequence'].to_i }
      expect(sequences).to eq((1..10).to_a)
    end
  end

  # ── Response routing ────────────────────────────────────────────────────────

  describe 'response routing' do
    it 'sets action_id from the ActionID header' do
      msgs = drain_chunks("Response: Success\r\nActionID: myid\r\n\r\n")
      expect(msgs.first[:action_id]).to eq('myid')
    end

    it 'sets action_id to nil when no ActionID header is present' do
      msgs = drain_chunks("Response: Follows\r\nPrivilege: Command\r\n\r\n")
      expect(msgs.first[:type]).to eq(:response)
      expect(msgs.first[:action_id]).to be_nil
    end

    it 'exposes a frozen raw string' do
      msgs = drain_chunks("Response: Error\r\nActionID: f2\r\n\r\n")
      expect(msgs.first[:raw]).to be_frozen
    end
  end

  # ── Event routing ───────────────────────────────────────────────────────────

  describe 'event routing' do
    it 'creates a frozen Event object with the correct name and headers' do
      msgs = drain_chunks("Event: Hangup\r\nChannel: SIP/200\r\nCause: 16\r\n\r\n")
      event = msgs.first[:event]
      expect(event).to be_a(RubyAsterisk::AMI::Event)
      expect(event).to be_frozen
      expect(event.name).to eq('Hangup')
      expect(event.headers['Cause']).to eq('16')
    end

    it 'Event object exposes the raw AMI message string' do
      raw_input = "Event: Hangup\r\nChannel: SIP/200\r\n\r\n"
      msgs = drain_chunks(raw_input)
      expect(msgs.first[:event].raw).to eq(raw_input)
    end
  end

  # ── AMI welcome banner tolerance ────────────────────────────────────────────

  describe 'AMI welcome banner tolerance' do
    it 'ignores the banner and still parses the subsequent response' do
      combined =
        "Asterisk Call Manager/1.1\n" \
        "Response: Success\r\nActionID: banner_test\r\n\r\n"

      msgs = drain_chunks(combined)
      expect(msgs.size).to eq(1)
      expect(msgs.first[:type]).to eq(:response)
      expect(msgs.first[:action_id]).to eq('banner_test')
    end
  end

  # ── build_message ────────────────────────────────────────────────────────────

  describe '.build_message' do
    it 'returns nil for frames with no recognised Response/Event header' do
      expect(described_class.build_message("Asterisk Call Manager/1.1\r\n\r\n")).to be_nil
    end

    it 'returns a frozen response hash' do
      msg = described_class.build_message("Response: OK\r\nActionID: x\r\n\r\n")
      expect(msg).to be_frozen
      expect(msg[:type]).to eq(:response)
    end

    it 'returns a frozen event hash' do
      msg = described_class.build_message("Event: Hangup\r\n\r\n")
      expect(msg).to be_frozen
      expect(msg[:type]).to eq(:event)
    end
  end
end
