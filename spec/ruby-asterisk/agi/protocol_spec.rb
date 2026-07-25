# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/agi/protocol'

RSpec.describe RubyAsterisk::AGI::Protocol do
  describe '.parse_response' do
    subject(:parse) { described_class.parse_response(line) }

    context 'with a plain success result' do
      let(:line) { '200 result=1' }

      it { expect(parse).to eq(code: 200, result: '1', data: nil) }
    end

    context 'with result=0' do
      let(:line) { '200 result=0' }

      it { expect(parse).to eq(code: 200, result: '0', data: nil) }
    end

    context 'with endpos extra data' do
      let(:line) { '200 result=0 endpos=12345' }

      it { expect(parse).to eq(code: 200, result: '0', data: 'endpos=12345') }
    end

    context 'with parenthetical extra data' do
      let(:line) { '200 result=1 (some text)' }

      it { expect(parse).to eq(code: 200, result: '1', data: 'some text') }
    end

    context 'with trailing newline' do
      let(:line) { "200 result=1\n" }

      it { expect(parse[:code]).to eq(200) }
      it { expect(parse[:result]).to eq('1') }
    end

    context 'with 510 error' do
      let(:line) { '510 Invalid or unknown command' }

      it { expect(parse).to eq(code: 510, result: nil, data: 'Invalid or unknown command') }
    end

    context 'with 511 error' do
      let(:line) { '511 Command Not Permitted on a dead channel' }

      it { expect(parse).to eq(code: 511, result: nil, data: 'Command Not Permitted on a dead channel') }
    end

    context 'with 520 single-line syntax error' do
      let(:line) { '520 Invalid command syntax' }

      it { expect(parse).to eq(code: 520, result: nil, data: 'Invalid command syntax') }
    end

    context 'with nil (socket EOF)' do
      let(:line) { nil }

      it { expect(parse).to eq(code: 0, result: nil, data: 'Connection closed') }
    end

    context 'with an unrecognised line' do
      let(:line) { 'INVALID' }

      it { expect(parse[:code]).to eq(0) }
    end
  end

  describe '.format_command' do
    it 'formats a bare command with no args' do
      expect(described_class.format_command('ANSWER')).to eq("ANSWER\n")
    end

    it 'appends plain args without quoting' do
      expect(described_class.format_command('WAIT FOR DIGIT', '5000')).to eq("WAIT FOR DIGIT 5000\n")
    end

    it 'wraps args that contain spaces in double quotes' do
      expect(described_class.format_command('VERBOSE', 'hello world', '1')).to eq(%(VERBOSE "hello world" 1\n))
    end

    it 'escapes backslashes inside quoted args' do
      expect(described_class.format_command('EXEC', 'foo', 'a\\b')).to eq(%(EXEC foo "a\\\\b"\n))
    end

    it 'escapes double quotes inside quoted args' do
      expect(described_class.format_command('EXEC', 'foo', 'say "hi"')).to eq(%(EXEC foo "say \\"hi\\""\n))
    end
  end

  describe '.escape_argument' do
    it 'returns "" for an empty string' do
      expect(described_class.escape_argument('')).to eq('""')
    end

    it 'returns the arg unchanged when no special chars' do
      expect(described_class.escape_argument('hello-world')).to eq('hello-world')
    end

    it 'wraps in quotes when arg contains a space' do
      expect(described_class.escape_argument('hello world')).to eq('"hello world"')
    end

    it 'escapes an internal backslash' do
      expect(described_class.escape_argument('a\\b')).to eq('"a\\\\b"')
    end

    it 'escapes an internal double-quote' do
      expect(described_class.escape_argument('say "hi"')).to eq('"say \\"hi\\""')
    end
  end

  describe '.quote' do
    it 'always wraps in double quotes even for plain strings' do
      expect(described_class.quote('hello-world')).to eq('"hello-world"')
    end

    it 'wraps an empty string' do
      expect(described_class.quote('')).to eq('""')
    end

    it 'escapes internal double quotes' do
      expect(described_class.quote('say "hi"')).to eq('"say \\"hi\\""')
    end

    it 'escapes internal backslashes' do
      expect(described_class.quote('a\\b')).to eq('"a\\\\b"')
    end
  end

  describe '.parse_env_line' do
    it 'returns [key, value] for a valid agi_ line' do
      expect(described_class.parse_env_line('agi_channel: SIP/test-1')).to eq(['agi_channel', 'SIP/test-1'])
    end

    it 'strips leading/trailing whitespace from the value' do
      expect(described_class.parse_env_line('agi_request:  agi://localhost  ')).to eq(['agi_request', 'agi://localhost'])
    end

    it 'returns nil for a non-agi line' do
      expect(described_class.parse_env_line('unexpected garbage')).to be_nil
    end

    it 'returns nil for a blank line' do
      expect(described_class.parse_env_line('')).to be_nil
    end
  end

  describe '.parse_env_block' do
    require 'stringio'

    it 'parses multiple agi_* lines into a hash' do
      io = StringIO.new("agi_channel: SIP/1001\nagi_callerid: 555\n\n")
      env = described_class.parse_env_block(io)

      expect(env).to eq('agi_channel' => 'SIP/1001', 'agi_callerid' => '555')
    end

    it 'stops at the blank line and ignores content after it' do
      io = StringIO.new("agi_channel: SIP/1001\n\nagi_after_blank: ignored\n")
      env = described_class.parse_env_block(io)

      expect(env).not_to have_key('agi_after_blank')
    end

    it 'yields unrecognised lines to the block' do
      io = StringIO.new("agi_channel: SIP/1001\nunknown line\n\n")
      unrecognised = []
      described_class.parse_env_block(io) { |l| unrecognised << l }

      expect(unrecognised).to eq(['unknown line'])
      expect(unrecognised.length).to eq(1)
    end

    it 'handles EOF gracefully (no blank line terminator)' do
      io = StringIO.new("agi_channel: SIP/1001\n")
      env = described_class.parse_env_block(io)

      expect(env).to eq('agi_channel' => 'SIP/1001')
    end
  end

  describe '.collect_multiline_error' do
    require 'stringio'

    let(:base_response) { { code: 520, result: nil, data: nil } }

    it 'returns first_response unchanged when first_line has no continuation marker' do
      io = StringIO.new('')
      result = described_class.collect_multiline_error('520 Invalid command syntax', base_response, io)

      expect(result).to equal(base_response)
    end

    it 'reads continuation lines until the closing NNN line and joins them' do
      continuation = "520-Usage: WAIT FOR DIGIT <timeout>\n520 End of proper usage.\n"
      io = StringIO.new(continuation)
      result = described_class.collect_multiline_error('520-Invalid command syntax.', base_response, io)

      expect(result[:code]).to eq(520)
      expect(result[:data]).to include('Invalid command syntax')
      expect(result[:data]).to include('WAIT FOR DIGIT')
    end

    it 'preserves the code from first_response' do
      continuation = "520-Details\n520 End of proper usage.\n"
      io = StringIO.new(continuation)
      result = described_class.collect_multiline_error('520-Intro', { code: 520, result: nil, data: nil }, io)

      expect(result[:code]).to eq(520)
    end

    it 'returns a frozen hash' do
      continuation = "520-Usage line\n520 End of proper usage.\n"
      io = StringIO.new(continuation)
      result = described_class.collect_multiline_error('520-Intro', base_response, io)

      expect(result).to be_frozen
    end
  end

  describe '.error?' do
    it 'returns true for 5xx codes' do
      expect(described_class.error?(code: 510, result: nil, data: 'x')).to be(true)
      expect(described_class.error?(code: 520, result: nil, data: 'x')).to be(true)
    end

    it 'returns false for 200' do
      expect(described_class.error?(code: 200, result: '1', data: nil)).to be(false)
    end

    it 'returns false for code 0' do
      expect(described_class.error?(code: 0, result: nil, data: 'x')).to be(false)
    end
  end
end
