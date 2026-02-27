# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/agi/protocol'

RSpec.describe RubyAsterisk::AGI::Protocol do
  # ── format_command ──────────────────────────────────────────────────────────

  describe '.format_command' do
    it 'formats a bare command with no arguments' do
      expect(described_class.format_command('ANSWER')).to eq("ANSWER\n")
    end

    it 'appends each argument separated by a space' do
      expect(described_class.format_command('EXEC', 'Playback', 'beep'))
        .to eq("EXEC Playback beep\n")
    end

    it 'terminates the line with \n' do
      expect(described_class.format_command('HANGUP')).to end_with("\n")
    end

    it 'accepts non-string arguments by calling to_s' do
      expect(described_class.format_command('WAIT', 'FOR', 'DIGIT', 5000))
        .to eq("WAIT FOR DIGIT 5000\n")
    end

    # ── argument escaping (acceptance criterion) ─────────────────────────────

    context 'with arguments requiring escaping' do
      it 'wraps an argument that contains a space in double quotes' do
        result = described_class.format_command('VERBOSE', 'hello world', '1')
        expect(result).to eq("VERBOSE \"hello world\" 1\n")
      end

      it 'escapes double-quote characters inside a quoted argument' do
        result = described_class.format_command('VERBOSE', 'say "hi"', '1')
        expect(result).to eq("VERBOSE \"say \\\"hi\\\"\" 1\n")
      end

      it 'escapes backslash characters inside a quoted argument' do
        result = described_class.format_command('VERBOSE', 'C:\\path', '1')
        expect(result).to eq("VERBOSE \"C:\\\\path\" 1\n")
      end

      it 'escapes both backslash and double-quote in the same argument' do
        result = described_class.format_command('VERBOSE', 'say \\"hi\\"', '1')
        expect(result).to eq("VERBOSE \"say \\\\\\\"hi\\\\\\\"\" 1\n")
      end

      it 'represents an empty argument as ""' do
        expect(described_class.format_command('GET', 'DATA', ''))
          .to eq("GET DATA \"\"\n")
      end

      it 'does not quote a plain argument that has no special characters' do
        result = described_class.format_command('STREAM', 'FILE', 'vm-greeting', '0123456789*#')
        expect(result).to eq("STREAM FILE vm-greeting 0123456789*#\n")
      end
    end
  end

  # ── parse_response ──────────────────────────────────────────────────────────

  describe '.parse_response' do
    # ── 200 success ────────────────────────────────────────────────────────

    context '200 success' do
      it 'parses a plain success result of 1' do
        result = described_class.parse_response("200 result=1\n")
        expect(result[:code]).to eq(200)
        expect(result[:result]).to eq('1')
        expect(result[:extra]).to be_nil
      end

      it 'parses a zero result (command ran but returned false/failure)' do
        result = described_class.parse_response("200 result=0\n")
        expect(result[:code]).to eq(200)
        expect(result[:result]).to eq('0')
        expect(result[:extra]).to be_nil
      end

      it 'parses a negative-one result (general error)' do
        result = described_class.parse_response("200 result=-1\n")
        expect(result[:code]).to eq(200)
        expect(result[:result]).to eq('-1')
        expect(result[:extra]).to be_nil
      end

      it 'parses extra data in parentheses (e.g. silence/dtmf reason)' do
        result = described_class.parse_response("200 result=0 (silence)\n")
        expect(result[:code]).to eq(200)
        expect(result[:result]).to eq('0')
        expect(result[:extra]).to eq('(silence)')
      end

      it 'parses a DTMF digit code with parenthesised character label' do
        result = described_class.parse_response("200 result=65 (A)\n")
        expect(result[:code]).to eq(200)
        expect(result[:result]).to eq('65')
        expect(result[:extra]).to eq('(A)')
      end

      it 'parses extra data in key=value form (e.g. stream file endpos)' do
        result = described_class.parse_response("200 result=1 endpos=123456\n")
        expect(result[:code]).to eq(200)
        expect(result[:result]).to eq('1')
        expect(result[:extra]).to eq('endpos=123456')
      end

      it 'handles a response without a trailing newline' do
        result = described_class.parse_response('200 result=1')
        expect(result[:code]).to eq(200)
        expect(result[:result]).to eq('1')
      end

      it 'strips surrounding whitespace before parsing' do
        result = described_class.parse_response('  200 result=1  ')
        expect(result[:code]).to eq(200)
        expect(result[:result]).to eq('1')
      end

      it 'returns a fully frozen hash with frozen string values' do
        result = described_class.parse_response("200 result=1 (silence)\n")
        expect(result).to be_frozen
        expect(result[:result]).to be_frozen
        expect(result[:extra]).to be_frozen
      end
    end

    # ── 510 invalid/unknown command ─────────────────────────────────────────

    context '510 invalid or unknown command' do
      it 'parses a 510 response and captures the error message as extra' do
        result = described_class.parse_response("510 Invalid or unknown command\n")
        expect(result[:code]).to eq(510)
        expect(result[:result]).to be_nil
        expect(result[:extra]).to eq('Invalid or unknown command')
      end

      it 'returns a frozen hash' do
        result = described_class.parse_response("510 Invalid or unknown command\n")
        expect(result).to be_frozen
      end
    end

    # ── 520 syntax error ────────────────────────────────────────────────────

    context '520 syntax error' do
      it 'parses the 520- continuation (intro) line' do
        raw = "520-Invalid command syntax.  Proper usage as follows:\n"
        result = described_class.parse_response(raw)
        expect(result[:code]).to eq(520)
        expect(result[:result]).to be_nil
        expect(result[:extra]).to eq('Invalid command syntax.  Proper usage as follows:')
      end

      it 'parses the closing 520 end-of-usage line' do
        result = described_class.parse_response("520 End of proper usage.\n")
        expect(result[:code]).to eq(520)
        expect(result[:result]).to be_nil
        expect(result[:extra]).to eq('End of proper usage.')
      end

      it 'returns a frozen hash' do
        result = described_class.parse_response("520 End of proper usage.\n")
        expect(result).to be_frozen
      end
    end

    # ── edge cases ──────────────────────────────────────────────────────────

    context 'edge cases' do
      it 'returns nil for an empty string' do
        expect(described_class.parse_response('')).to be_nil
      end

      it 'returns nil for a whitespace-only string' do
        expect(described_class.parse_response("   \n")).to be_nil
      end

      it 'returns nil for an unrecognisable line' do
        expect(described_class.parse_response('not a valid response')).to be_nil
      end

      it 'sets extra to nil when there is no text after the code on a non-result line' do
        # Bare code with nothing after it (degenerate case).
        result = described_class.parse_response('510 ')
        expect(result).not_to be_nil
        expect(result[:extra]).to be_nil
      end
    end
  end

  # ── escape_argument (public helper) ─────────────────────────────────────────

  describe '.escape_argument' do
    it 'returns a plain argument unchanged' do
      expect(described_class.escape_argument('hello')).to eq('hello')
    end

    it 'returns "" for an empty argument' do
      expect(described_class.escape_argument('')).to eq('""')
    end

    it 'wraps an argument with spaces in double quotes' do
      expect(described_class.escape_argument('hello world')).to eq('"hello world"')
    end

    it 'escapes internal double quotes' do
      expect(described_class.escape_argument('say "hi"')).to eq('"say \"hi\""')
    end

    it 'escapes internal backslashes' do
      expect(described_class.escape_argument('C:\\path')).to eq('"C:\\\\path"')
    end

    it 'wraps an argument containing only a backslash' do
      expect(described_class.escape_argument('\\')).to eq('"\\\\"')
    end
  end
end
