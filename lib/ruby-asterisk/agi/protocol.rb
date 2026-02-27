# frozen_string_literal: true

module RubyAsterisk
  module AGI
    ##
    # Low-level formatter and parser for the Asterisk Gateway Interface (AGI)
    # protocol.
    #
    # == AGI command format
    #
    #   COMMAND [arg1] [arg2] ...\n
    #
    # Arguments that contain whitespace, double-quotes, or backslashes are
    # automatically wrapped in double quotes with internal special characters
    # escaped.
    #
    # == AGI response format
    #
    #   200 result=VALUE [extra data]\n    # success
    #   510 Invalid or unknown command\n  # unknown command
    #   520-Invalid command syntax. ...\n # syntax error (multi-line intro)
    #   520 End of proper usage.\n        # syntax error (closing line)
    #
    # Responses carrying a +result=+ field are parsed into +:code+, +:result+,
    # and +:extra+ keys.  Responses without a +result=+ field (510, 520 lines)
    # carry +:code+ and +:extra+ only (with +:result+ set to +nil+).
    #
    module Protocol
      # Line terminator appended to every formatted command.
      LINE_TERMINATOR = "\n"

      # Matches a response that carries a result value:
      #   CODE result=VALUE [optional extra]
      RESULT_RE = /\A(\d{3})\s+result=(\S+)(?:\s+(.*?))?\s*\z/

      # Matches a response line without a result field:
      #   CODE[-space]message text  (separator and message are both optional)
      CODE_RE = /\A(\d{3})(?:[-\s](.*?))?\s*\z/

      # Format an AGI command string ready for sending to Asterisk.
      #
      # @param command [String]      the AGI command verb (e.g. "ANSWER", "EXEC")
      # @param args    [Array<#to_s>] zero or more command arguments
      # @return [String] formatted command terminated with \n
      def self.format_command(command, *args)
        parts = [command.to_s]
        args.each { |a| parts << escape_argument(a.to_s) }
        "#{parts.join(' ')}#{LINE_TERMINATOR}"
      end

      # Parse a single raw AGI response line into a structured hash.
      #
      # @param raw [String] one response line from Asterisk (trailing \n is stripped)
      # @return [Hash, nil] frozen hash with keys:
      #   :code   [Integer]      three-digit status code
      #   :result [String, nil]  value from "result=VALUE" (nil when not present)
      #   :extra  [String, nil]  trailing text after the result field, or the
      #                          error message for 510/520 lines
      # @return [nil] if +raw+ cannot be recognised as a valid AGI response
      def self.parse_response(raw)
        line = raw.to_s.strip
        return nil if line.empty?

        parse_result_line(line) || parse_code_line(line)
      end

      # Escape a single AGI command argument.
      #
      # Plain arguments are returned as-is.  If the argument is empty, or
      # contains whitespace, double-quotes, or backslashes, it is wrapped in
      # double quotes with internal special characters escaped.
      #
      # @param arg [String]
      # @return [String] escaped (and possibly quoted) argument
      def self.escape_argument(arg)
        return '""' if arg.empty?
        return arg unless arg.match?(/[\s"\\]/)

        escaped = arg
                  .gsub('\\') { '\\\\' }
                  .gsub('"')  { '\\"' }
        "\"#{escaped}\""
      end

      # -- private helpers ----------------------------------------------------

      def self.parse_result_line(line)
        m = RESULT_RE.match(line)
        return nil unless m

        extra = m[3]&.strip
        { code: m[1].to_i,
          result: m[2].freeze,
          extra: (extra.nil? || extra.empty? ? nil : extra.freeze) }.freeze
      end
      private_class_method :parse_result_line

      def self.parse_code_line(line)
        m = CODE_RE.match(line)
        return nil unless m

        msg = m[2]&.strip || ''
        { code: m[1].to_i, result: nil,
          extra: (msg.empty? ? nil : msg.freeze) }.freeze
      end
      private_class_method :parse_code_line
    end
  end
end
