# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/agi/session'
require 'stringio'

RSpec.describe RubyAsterisk::AGI::Session do
  # A fake socket backed by StringIO for reads and a StringIO capture for writes.
  def fake_socket(input_string, responses: [])
    reader = StringIO.new(input_string)
    writer = StringIO.new
    socket = double('socket')

    allow(socket).to receive(:gets) do
      line = reader.gets
      line || responses.shift
    end
    allow(socket).to receive(:write) { |data| writer.write(data) }

    [socket, writer]
  end

  # Builds a socket whose reads cycle through env_block then response_lines
  def session_socket(env_block, response_lines)
    all_input = env_block + response_lines.map { |l| "#{l}\n" }.join
    socket, writer = fake_socket(all_input)
    [socket, writer]
  end

  let(:logger) { instance_double(Logger, debug: nil, info: nil, warn: nil, error: nil) }

  describe '#read_env' do
    it 'parses agi_* key/value pairs from the env block' do
      env_block = "agi_channel: SIP/test-1\nagi_callerid: 1000\n\n"
      socket, = fake_socket(env_block)
      session = described_class.new(socket, logger: logger)
      session.read_env

      expect(session.env['agi_channel']).to eq('SIP/test-1')
      expect(session.env['agi_callerid']).to eq('1000')
    end

    it 'stops at the blank line' do
      env_block = "agi_channel: SIP/test-1\n\nagi_after_blank: ignored\n"
      socket, = fake_socket(env_block)
      session = described_class.new(socket, logger: logger)
      session.read_env

      expect(session.env).not_to have_key('agi_after_blank')
    end

    it 'ignores non-agi lines with a debug log' do
      env_block = "agi_channel: SIP/x\nunknown line\n\n"
      socket, = fake_socket(env_block)
      session = described_class.new(socket, logger: logger)
      session.read_env

      expect(logger).to have_received(:debug).with(/unexpected line/)
      expect(session.env.keys).to eq(['agi_channel'])
    end
  end

  describe '#execute' do
    subject(:session) { described_class.new(socket, logger: logger) }

    let(:socket) do
      s, = session_socket('', ['200 result=1'])
      s
    end

    it 'returns a parsed response hash' do
      result = session.execute('ANSWER')
      expect(result).to eq(code: 200, result: '1', data: nil)
    end

    it 'raises RubyAsterisk::Error on 5xx response' do
      s = double('socket')
      allow(s).to receive(:write)
      allow(s).to receive(:gets).and_return("510 Invalid or unknown command\n")
      session = described_class.new(s, logger: logger)

      expect { session.execute('BADCMD') }.to raise_error(RubyAsterisk::Error, /510/)
    end

    it 'raises RubyAsterisk::Error on EOF (nil)' do
      s = double('socket')
      allow(s).to receive(:write)
      allow(s).to receive(:gets).and_return(nil)
      session = described_class.new(s, logger: logger)

      expect { session.execute('ANSWER') }.to raise_error(RubyAsterisk::Error)
    end
  end

  describe 'command wrappers' do
    let(:written) { StringIO.new }
    let(:socket) do
      s = double('socket')
      allow(s).to receive(:write) { |data| written.write(data) }
      allow(s).to receive(:gets).and_return("200 result=1\n")
      s
    end
    subject(:session) { described_class.new(socket, logger: logger) }

    it '#answer writes ANSWER command' do
      session.answer
      expect(written.string).to eq("ANSWER\n")
    end

    it '#hangup writes HANGUP without channel' do
      session.hangup
      expect(written.string).to eq("HANGUP\n")
    end

    it '#hangup writes HANGUP with channel' do
      session.hangup('SIP/1001')
      expect(written.string).to eq("HANGUP SIP/1001\n")
    end

    it '#stream_file quotes filename and escape_digits' do
      session.stream_file('hello-world', '#*')
      expect(written.string).to eq(%(STREAM FILE "hello-world" "#*"\n))
    end

    it '#stream_file uses empty escape_digits by default' do
      session.stream_file('hello-world')
      expect(written.string).to eq(%(STREAM FILE "hello-world" ""\n))
    end

    it '#say_digits writes SAY DIGITS command' do
      session.say_digits('1234')
      expect(written.string).to eq(%(SAY DIGITS 1234 ""\n))
    end

    it '#say_number writes SAY NUMBER command' do
      session.say_number(42)
      expect(written.string).to eq(%(SAY NUMBER 42 ""\n))
    end

    it '#exec writes EXEC command with joined args' do
      session.exec('AGICommand', 'arg1', 'arg2')
      expect(written.string).to eq(%(EXEC AGICommand "arg1,arg2"\n))
    end

    it '#set_variable writes SET VARIABLE command' do
      session.set_variable('MYVAR', 'hello')
      expect(written.string).to eq(%(SET VARIABLE MYVAR "hello"\n))
    end

    it '#get_variable writes GET VARIABLE command' do
      session.get_variable('MYVAR')
      expect(written.string).to eq("GET VARIABLE MYVAR\n")
    end

    it '#get_data writes GET DATA command with defaults' do
      session.get_data('silence')
      expect(written.string).to eq(%(GET DATA "silence" 5000 1024\n))
    end

    it '#get_data accepts timeout and max_digits overrides' do
      session.get_data('beep', timeout: 3000, max_digits: 4)
      expect(written.string).to eq(%(GET DATA "beep" 3000 4\n))
    end

    it '#verbose writes VERBOSE command' do
      session.verbose('test message', level: 2)
      expect(written.string).to eq(%(VERBOSE "test message" 2\n))
    end

    it '#exec escapes args containing commas correctly' do
      session.exec('AGI', 'arg,with,commas', 'say "hi"')
      expect(written.string).to eq(%(EXEC AGI "arg,with,commas,say \\"hi\\""\n))
    end

    # -- Telephony commands ---------------------------------------------------

    it '#dial writes EXEC Dial with target and timeout' do
      session.dial('SIP/1001', timeout: 30)
      expect(written.string).to eq(%(EXEC Dial "SIP/1001,30"\n))
    end

    it '#dial includes options when provided' do
      session.dial('SIP/1001', timeout: 15, options: 'r')
      expect(written.string).to eq(%(EXEC Dial "SIP/1001,15,r"\n))
    end

    it '#wait_for_digit writes WAIT FOR DIGIT with timeout' do
      session.wait_for_digit(3000)
      expect(written.string).to eq("WAIT FOR DIGIT 3000\n")
    end

    it '#wait_for_digit uses 5000ms default timeout' do
      session.wait_for_digit
      expect(written.string).to eq("WAIT FOR DIGIT 5000\n")
    end

    it '#record_file writes RECORD FILE with beep by default' do
      session.record_file('recording', format: 'wav', escape_digits: '#', timeout_ms: 10_000, offset: 0)
      expect(written.string).to eq(%(RECORD FILE "recording" wav "#" 10000 0 BEEP\n))
    end

    it '#record_file includes silence param when provided' do
      session.record_file('msg', silence: 5)
      expect(written.string).to eq(%(RECORD FILE "msg" wav "#" -1 0 BEEP s=5\n))
    end

    it '#record_file omits BEEP when beep: false' do
      session.record_file('msg', beep: false)
      expect(written.string).to eq(%(RECORD FILE "msg" wav "#" -1 0\n))
    end

    it '#send_text writes SEND TEXT with quoted message' do
      session.send_text('hello world')
      expect(written.string).to eq(%(SEND TEXT "hello world"\n))
    end

    it '#send_image writes SEND IMAGE with filename' do
      session.send_image('logo.png')
      expect(written.string).to eq("SEND IMAGE logo.png\n")
    end

    it '#channel_status writes CHANNEL STATUS without arg by default' do
      session.channel_status
      expect(written.string).to eq("CHANNEL STATUS\n")
    end

    it '#channel_status writes CHANNEL STATUS with a channel name' do
      session.channel_status('SIP/1001')
      expect(written.string).to eq("CHANNEL STATUS SIP/1001\n")
    end

    # -- AstDB commands -------------------------------------------------------

    it '#database_get writes DATABASE GET command' do
      session.database_get('family', 'key')
      expect(written.string).to eq("DATABASE GET family key\n")
    end

    it '#database_put writes DATABASE PUT command with quoted value' do
      session.database_put('family', 'key', 'hello world')
      expect(written.string).to eq(%(DATABASE PUT family key "hello world"\n))
    end

    it '#database_del writes DATABASE DEL command' do
      session.database_del('family', 'key')
      expect(written.string).to eq("DATABASE DEL family key\n")
    end

    it '#database_deltree writes DATABASE DELTREE without subtree' do
      session.database_deltree('family')
      expect(written.string).to eq("DATABASE DELTREE family\n")
    end

    it '#database_deltree writes DATABASE DELTREE with subtree' do
      session.database_deltree('family', 'sub/tree')
      expect(written.string).to eq("DATABASE DELTREE family sub/tree\n")
    end
  end

  describe 'multi-line 520 error handling' do
    let(:logger) { instance_double(Logger, debug: nil, info: nil, warn: nil, error: nil) }

    it 'raises with the accumulated body for a 520- intro followed by 520 closer' do
      lines = [
        "520-Invalid command syntax.  Proper usage follows:\n",
        "520-Usage: WAIT FOR DIGIT <timeout>\n",
        "520 End of proper usage.\n"
      ]
      socket = double('socket')
      allow(socket).to receive(:write)
      allow(socket).to receive(:gets).and_return(*lines)
      session = described_class.new(socket, logger: logger)

      expect { session.execute('BADCMD') }
        .to raise_error(RubyAsterisk::Error, /Invalid command syntax/)
    end

    it 'accumulates the usage lines into the error message' do
      lines = [
        "520-Invalid command syntax.  Proper usage follows:\n",
        "520-Usage: WAIT FOR DIGIT <timeout>\n",
        "520 End of proper usage.\n"
      ]
      socket = double('socket')
      allow(socket).to receive(:write)
      allow(socket).to receive(:gets).and_return(*lines)
      session = described_class.new(socket, logger: logger)

      expect { session.execute('BADCMD') }
        .to raise_error(RubyAsterisk::Error, /WAIT FOR DIGIT/)
    end
  end
end
