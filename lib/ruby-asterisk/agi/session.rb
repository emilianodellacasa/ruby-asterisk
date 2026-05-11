# frozen_string_literal: true

require 'logger'
require_relative 'protocol'
require_relative '../../ruby-asterisk/error'

module RubyAsterisk
  module AGI
    # Wraps a single FastAGI connection.
    #
    # Parses the AGI environment block sent by Asterisk at connection start,
    # then provides command methods that write AGI commands and return parsed
    # response hashes.
    class Session
      attr_reader :env, :socket

      def initialize(socket, logger: Logger.new($stdout))
        @socket = socket
        @logger = logger
        @env    = {}
      end

      # Read the AGI environment block (agi_key: value lines until blank line).
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

      # Send a raw AGI command and return the parsed response Hash.
      #
      # @param command_string [String]
      # @return [Hash] { code: Integer, result: String|nil, data: String|nil }
      # @raise [RubyAsterisk::Error] on EOF or 5xx response
      def execute(command_string)
        @socket.write("#{command_string}\n")
        line = @socket.gets
        raise Error, 'Connection closed by Asterisk' unless line

        response = Protocol.parse_response(line)
        raise Error, "AGI error (#{response[:code]}): #{response[:data]}" if response[:code] >= 500

        response
      end

      def answer
        execute('ANSWER')
      end

      def hangup(channel = nil)
        execute(channel ? "HANGUP #{channel}" : 'HANGUP')
      end

      def stream_file(filename, escape_digits = '')
        execute(%(STREAM FILE "#{filename}" "#{escape_digits}"))
      end

      def say_digits(digits, escape_digits = '')
        execute(%(SAY DIGITS #{digits} "#{escape_digits}"))
      end

      def say_number(number, escape_digits = '')
        execute(%(SAY NUMBER #{number} "#{escape_digits}"))
      end

      def exec(application, *args)
        execute(%(EXEC #{application} "#{args.join(',')}"))
      end

      def set_variable(name, value)
        execute(%(SET VARIABLE #{name} "#{value}"))
      end

      def get_variable(name)
        execute("GET VARIABLE #{name}")
      end

      def get_data(filename, timeout: 5000, max_digits: 1024)
        execute(%(GET DATA "#{filename}" #{timeout} #{max_digits}))
      end

      def verbose(message, level: 1)
        execute(%(VERBOSE "#{message}" #{level}))
      end
    end
  end
end
