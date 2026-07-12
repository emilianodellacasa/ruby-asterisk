# frozen_string_literal: true

require 'logger'
require_relative 'protocol'
require_relative '../../ruby-asterisk/error'

module RubyAsterisk
  module AGI
    # Wraps a single FastAGI connection lifecycle.
    #
    # Parses the AGI environment block sent by Asterisk at connection start,
    # then provides command methods that write AGI commands and return parsed
    # response hashes.  Under an Async Fiber scheduler the socket reads/writes
    # yield the Fiber rather than blocking a thread.
    class Session
      attr_reader :env, :socket

      # @param env_timeout [Numeric, nil] seconds to wait for the initial AGI
      #   environment block before giving up (guards against slowloris-style
      #   connect-and-stall clients). Applied only to the handshake, never to
      #   command reads (which may legitimately block for minutes, e.g. STREAM
      #   FILE). Pass nil to disable. No-op on Ruby 3.1 (IO#timeout= shim).
      def initialize(socket, logger: Logger.new($stdout), env_timeout: 10)
        @socket      = socket
        @logger      = logger
        @env         = {}
        @env_timeout = env_timeout
      end

      # Read the initial AGI environment block (agi_key: value lines until blank line).
      #
      # @raise [IO::TimeoutError] on Ruby >= 3.2 if the peer stalls beyond env_timeout
      def read_env
        with_env_timeout do
          @env = Protocol.parse_env_block(@socket) do |line|
            @logger.debug("AGI env: unexpected line: #{line}")
          end
        end
      end

      # Send a raw AGI command string and return the parsed response Hash.
      #
      # Handles Asterisk's two-line 520- syntax-error format by accumulating
      # continuation lines until the closing `520 End of proper usage.` line.
      #
      # Any embedded CR/LF in +command_string+ is stripped before sending: AGI is
      # a line-oriented protocol, so a newline in a (possibly caller-controlled)
      # argument or identifier would otherwise inject additional commands.
      #
      # @param command_string [String]
      # @return [Hash] { code: Integer, result: String|nil, data: String|nil }
      # @raise [RubyAsterisk::Error] on EOF or 5xx response
      # @raise [RubyAsterisk::HangupError] if Asterisk sends an out-of-band HANGUP
      def execute(command_string)
        line = command_string.to_s.delete("\r\n")
        @socket.write("#{line}\n")
        line = @socket.gets
        raise Error, 'Connection closed by Asterisk' unless line
        raise HangupError, 'Channel hung up' if line.chomp == 'HANGUP'

        response = Protocol.parse_response(line)

        if response[:code] >= 500
          response = Protocol.collect_multiline_error(line.chomp, response, @socket)
          raise Error, "AGI error (#{response[:code]}): #{response[:data]}"
        end

        response
      end

      # -- Existing wrappers (rewritten to use Protocol.format_command) -------

      def answer
        execute('ANSWER')
      end

      def hangup(channel = nil)
        channel ? execute("HANGUP #{channel}") : execute('HANGUP')
      end

      def stream_file(filename, escape_digits = '')
        execute("STREAM FILE #{Protocol.quote(filename)} #{Protocol.quote(escape_digits)}")
      end

      def say_digits(digits, escape_digits = '')
        execute("SAY DIGITS #{digits} #{Protocol.escape_argument(escape_digits)}")
      end

      def say_number(number, escape_digits = '')
        execute("SAY NUMBER #{number} #{Protocol.escape_argument(escape_digits)}")
      end

      def exec(application, *args)
        execute("EXEC #{application} #{Protocol.quote(args.join(','))}")
      end

      def set_variable(name, value)
        execute("SET VARIABLE #{name} #{Protocol.quote(value)}")
      end

      def get_variable(name)
        execute("GET VARIABLE #{name}")
      end

      def get_data(filename, timeout: 5000, max_digits: 1024)
        execute("GET DATA #{Protocol.quote(filename)} #{timeout} #{max_digits}")
      end

      def verbose(message, level: 1)
        execute("VERBOSE #{Protocol.quote(message)} #{level}")
      end

      # -- Telephony commands -------------------------------------------------

      # Originate a call leg via Dial dialplan application.
      def dial(target, timeout: 30, options: '')
        args = [target, timeout.to_s]
        args << options unless options.to_s.empty?
        execute("EXEC Dial #{Protocol.quote(args.join(','))}")
      end

      # Block until a DTMF digit is pressed or timeout expires.
      # Like every verb this returns the parsed response Hash
      # { code:, result:, data: }; the pressed key's decimal ASCII value
      # (or -1 on timeout) is in response[:result].
      def wait_for_digit(timeout_ms = 5000)
        execute("WAIT FOR DIGIT #{timeout_ms}")
      end

      # Record audio to a file.
      def record_file(filename, format: 'wav', escape_digits: '#', timeout_ms: -1, offset: 0, beep: true, silence: nil)
        cmd = "RECORD FILE #{Protocol.quote(filename)} #{format} " \
              "#{Protocol.quote(escape_digits)} #{timeout_ms} #{offset}"
        cmd += ' BEEP' if beep
        cmd += " s=#{silence}" if silence
        execute(cmd)
      end

      def send_text(text)
        execute("SEND TEXT #{Protocol.quote(text)}")
      end

      def send_image(filename)
        execute("SEND IMAGE #{filename}")
      end

      def channel_status(channel = nil)
        channel ? execute("CHANNEL STATUS #{channel}") : execute('CHANNEL STATUS')
      end

      # -- AstDB commands -----------------------------------------------------

      def database_get(family, key)
        execute("DATABASE GET #{family} #{key}")
      end

      def database_put(family, key, value)
        execute("DATABASE PUT #{family} #{key} #{Protocol.quote(value)}")
      end

      def database_del(family, key)
        execute("DATABASE DEL #{family} #{key}")
      end

      def database_deltree(family, keytree = nil)
        keytree ? execute("DATABASE DELTREE #{family} #{keytree}") : execute("DATABASE DELTREE #{family}")
      end

      private

      # Apply @env_timeout to the socket for the duration of the block, then
      # restore it. No-op when the timeout is nil or the socket does not support
      # IO#timeout= (Ruby 3.1 shim is a no-op; test doubles simply skip it).
      def with_env_timeout
        return yield if @env_timeout.nil? || !@socket.respond_to?(:timeout=)

        previous = @socket.respond_to?(:timeout) ? @socket.timeout : nil
        @socket.timeout = @env_timeout
        begin
          yield
        ensure
          @socket.timeout = previous
        end
      end
    end
  end
end
