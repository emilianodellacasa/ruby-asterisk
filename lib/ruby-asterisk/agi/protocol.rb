# frozen_string_literal: true

module RubyAsterisk
  module AGI
    # Stateless helpers for the FastAGI wire protocol.
    module Protocol
      ENV_LINE = /\A(agi_\w+):\s*(.*)/
      RESPONSE_LINE = /\A(\d{3})\s+(.*)$/

      # Parse a single AGI response line returned by Asterisk.
      #
      # Supported formats:
      #   200 result=<value>
      #   200 result=<value> endpos=<n>
      #   200 result=<value> (<extra text>)
      #   510 Invalid or unknown command
      #
      # @param line [String, nil]
      # @return [Hash] with keys :code (Integer), :result (String|nil), :data (String|nil)
      def self.parse_response(line)
        return { code: 0, result: nil, data: 'Connection closed' } if line.nil?

        m = RESPONSE_LINE.match(line.chomp)
        return { code: 0, result: nil, data: line.chomp } unless m

        code = m[1].to_i
        rest = m[2]

        result, data = extract_result_and_data(rest)
        { code: code, result: result, data: data }
      end

      # @param rest [String] everything after the status code
      # @return [Array(String|nil, String|nil)]
      def self.extract_result_and_data(rest)
        if (rm = rest.match(/\Aresult=(\S*)\s*(.*)?/))
          result = rm[1].empty? ? nil : rm[1]
          extra  = rm[2].strip
          data   = extra.empty? ? nil : extra.delete_prefix('(').delete_suffix(')')
          [result, data]
        else
          [nil, rest.strip.empty? ? nil : rest.strip]
        end
      end
      private_class_method :extract_result_and_data
    end
  end
end
