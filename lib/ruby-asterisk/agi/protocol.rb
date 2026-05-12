# frozen_string_literal: true

module RubyAsterisk
  module AGI
    # Low-level formatter and parser for the FastAGI wire protocol.
    module Protocol
      ENV_LINE = /\A(agi_\w+):\s*(.*)/

      # Matches a response carrying a result value:  CODE result=VALUE [extra]
      RESULT_RE = /\A(\d{3})\s+result=(\S+)(?:\s+(.*?))?\s*\z/

      # Matches any response line (fallback):  CODE[-space]message
      CODE_RE = /\A(\d{3})(?:[-\s](.*?))?\s*\z/

      # Format an AGI command string ready for sending to Asterisk.
      #
      # @param command [String]       AGI command verb (e.g. "ANSWER", "EXEC")
      # @param args    [Array<#to_s>] zero or more arguments
      # @return [String] space-joined, \n-terminated line
      def self.format_command(command, *args)
        parts = [command.to_s]
        args.each { |a| parts << escape_argument(a.to_s) }
        "#{parts.join(' ')}\n"
      end

      # Escape a single AGI command argument.
      #
      # Plain alphanumeric/dash/underscore/slash tokens are returned as-is.
      # Empty strings and strings containing whitespace, quotes, or backslashes
      # are double-quoted with internal special characters escaped.
      #
      # @param arg [String]
      # @return [String]
      def self.escape_argument(arg)
        return '""' if arg.empty?
        return arg unless arg.match?(/[\s"\\]/)

        escaped = arg.gsub('\\') { '\\\\' }.gsub('"') { '\\"' }
        "\"#{escaped}\""
      end

      # Always wrap +arg+ in double quotes, escaping any internal backslashes
      # and double-quotes. Use for AGI arguments that Asterisk requires to be
      # quoted regardless of content (filenames, variable values, messages).
      #
      # @param arg [String, #to_s]
      # @return [String]
      def self.quote(arg)
        escaped = arg.to_s.gsub('\\') { '\\\\' }.gsub('"') { '\\"' }
        "\"#{escaped}\""
      end

      # Parse a single raw AGI response line into a frozen Hash.
      #
      # @param line [String, nil]
      # @return [Hash] { code: Integer, result: String|nil, data: String|nil }
      def self.parse_response(line)
        return { code: 0, result: nil, data: 'Connection closed' }.freeze if line.nil?

        stripped = line.chomp
        return { code: 0, result: nil, data: stripped }.freeze if stripped.empty?

        parse_result_line(stripped) || parse_code_line(stripped) ||
          { code: 0, result: nil, data: stripped }.freeze
      end

      # @param response [Hash] as returned by {parse_response}
      # @return [Boolean] true when the response code signals an error
      def self.error?(response)
        response[:code] >= 500
      end

      # -- private helpers ----------------------------------------------------

      def self.parse_result_line(line)
        m = RESULT_RE.match(line)
        return nil unless m

        extra = m[3]&.strip
        data = extra.nil? || extra.empty? ? nil : extra.delete_prefix('(').delete_suffix(')')
        { code: m[1].to_i, result: m[2].freeze, data: data&.freeze }.freeze
      end
      private_class_method :parse_result_line

      def self.parse_code_line(line)
        m = CODE_RE.match(line)
        return nil unless m

        msg = m[2]&.strip || ''
        { code: m[1].to_i, result: nil, data: (msg.empty? ? nil : msg.freeze) }.freeze
      end
      private_class_method :parse_code_line
    end
  end
end
