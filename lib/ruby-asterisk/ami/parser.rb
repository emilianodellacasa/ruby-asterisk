# frozen_string_literal: true

require 'ruby-asterisk/ami/event'

module RubyAsterisk
  module AMI
    # Stateless module for parsing raw AMI byte streams into structured messages.
    #
    # All methods are class-level and side-effect free; they can be called from
    # any thread or Fiber without synchronization.
    module Parser
      DELIMITER     = "\r\n\r\n"
      DELIMITER_LEN = DELIMITER.length

      # Parses "Key: Value\r\n..." lines into a frozen hash.
      # Lines without a colon separator (e.g. the AMI welcome banner) are skipped.
      def self.parse_headers(raw)
        headers = {}
        raw.split(/\r?\n/).each do |line|
          next if line.empty?

          colon = line.index(':')
          next unless colon&.positive?

          headers[line[0, colon].freeze] = line[(colon + 1)..].strip.freeze
        end
        headers.freeze
      end

      # Extracts all complete AMI messages from +buffer+ (mutates it) and
      # yields a frozen message hash for each one.
      #
      # @param buffer [String] mutable accumulation buffer
      # @yieldparam msg [Hash] frozen: { type: :response|:event, headers:, raw:, action_id: }
      def self.drain(buffer)
        while (idx = buffer.index(DELIMITER))
          raw = buffer.slice!(0, idx + DELIMITER_LEN)
          msg = build_message(raw)
          yield msg if msg
        end
      end

      # Builds a single frozen message hash from a raw AMI frame, or nil if the
      # frame carries no recognised Response/Event header.
      def self.build_message(raw)
        headers = parse_headers(raw)
        return nil if headers.empty?

        frozen_raw = raw.freeze
        if headers.key?('Response')
          { type: :response, headers: headers, raw: frozen_raw,
            action_id: headers['ActionID'] }.freeze
        elsif headers.key?('Event')
          { type: :event,
            event: RubyAsterisk::AMI::Event.new(headers, frozen_raw) }.freeze
        end
      end
    end
  end
end
