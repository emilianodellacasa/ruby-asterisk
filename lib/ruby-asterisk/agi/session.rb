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

      def initialize(socket, logger: Logger.new($stdout))
        @socket = socket
        @logger = logger
        @env    = {}
      end

      # Read the initial AGI environment block (agi_key: value lines until blank line).
      def read_env
        while (line = @socket.gets)
          break if line.chomp.empty?

          m = Protocol::ENV_LINE.match(line.chomp)
          if m
            @env[m[1]] = m[2].strip
          else
            @logger.debug("AGI env: unexpected line: #{line.chomp}")
          end
        end
      end

      # Send a raw AGI command string and return the parsed response Hash.
      #
      # Handles Asterisk's two-line 520- syntax-error format by accumulating
      # continuation lines until the closing `520 End of proper usage.` line.
      #
      # @param command_string [String]
      # @return [Hash] { code: Integer, result: String|nil, data: String|nil }
      # @raise [RubyAsterisk::Error] on EOF or 5xx response
      def execute(command_string)
        @socket.write("#{command_string}\n")
        line = @socket.gets
        raise Error, 'Connection closed by Asterisk' unless line

        response = Protocol.parse_response(line)

        if response[:code] >= 500
          response = collect_multiline_error(line.chomp, response)
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
      # Returns the decimal ASCII value of the key, or -1 on timeout.
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

      # When the first error line is a multi-line intro (e.g. `520-Invalid…`),
      # accumulate continuation lines until the `520 End of proper usage.` closer.
      def collect_multiline_error(first_line, first_response)
        return first_response unless first_line.match?(/\A\d{3}-/)

        lines = [first_line.sub(/\A\d{3}-/, '')]
        while (l = @socket.gets)
          chopped = l.chomp
          if chopped.match?(/\A\d{3}\s/)
            lines << chopped.sub(/\A\d{3}\s*/, '')
            break
          else
            lines << chopped.sub(/\A\d{3}-/, '')
          end
        end

        body = lines.reject(&:empty?).join(' ')
        { code: first_response[:code], result: nil, data: body.freeze }.freeze
      end
    end
  end
end
