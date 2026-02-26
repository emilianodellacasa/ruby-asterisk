# frozen_string_literal: true

require 'ruby-asterisk/ami/event'

module RubyAsterisk
  module AMI
    ##
    # Ractor that receives raw frozen string chunks from SocketReaderRactor,
    # reassembles fragmented AMI messages, parses their headers, and forwards
    # fully formed, frozen Response or Event descriptors to the consumer Ractor.
    #
    # Pipeline:
    #   SocketReaderRactor  -->  ParserRactor  -->  AMI::Client (consumer)
    #
    # Input messages (from SocketReaderRactor):
    #   { type: :data,         data: frozen_string }
    #   { type: :connected,    host:, port: }
    #   { type: :disconnected, reason: }
    #   { type: :error,        message: }
    #   { type: :stop }
    #
    # Output messages (sent to consumer):
    #   { type: :response, headers: frozen_hash, raw: frozen_string, action_id: string_or_nil }
    #   { type: :event,    event: frozen_Event }
    #   { type: :connected,    host:, port: }   (forwarded)
    #   { type: :disconnected, reason: }        (forwarded)
    #   { type: :error,        message: }       (forwarded)
    #
    class ParserRactor
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

      # Sends one parsed message to the consumer based on its headers.
      def self.dispatch(raw, consumer)
        headers = parse_headers(raw)
        return if headers.empty?

        frozen_raw = raw.freeze
        if headers.key?('Response')
          consumer.send({ type: :response, headers: headers, raw: frozen_raw,
                          action_id: headers['ActionID'] }.freeze)
        elsif headers.key?('Event')
          consumer.send({ type: :event,
                          event: RubyAsterisk::AMI::Event.new(headers, frozen_raw) }.freeze)
        end
      end

      # Extracts and dispatches all complete messages from the buffer.
      def self.drain(buffer, consumer)
        while (idx = buffer.index(DELIMITER))
          raw = buffer.slice!(0, idx + DELIMITER_LEN)
          dispatch(raw, consumer)
        end
      end

      # Defined as a constant proc so the Ractor block closes over nothing
      # non-shareable. All heavy lifting is delegated to class methods above.
      RACTOR_LOGIC = proc do |consumer|
        buffer = +''
        loop do
          msg = Ractor.receive
          case msg[:type]
          when :data
            buffer << msg[:data]
            ParserRactor.drain(buffer, consumer)
          when :connected, :disconnected, :error
            consumer.send(msg)
          when :stop
            break
          end
        end
      end

      # @param consumer [Ractor] the Ractor that will receive parsed messages.
      def initialize(consumer)
        @ractor = Ractor.new(consumer, &RACTOR_LOGIC)
      end

      ##
      # The underlying Ractor — pass to SocketReaderRactor#start(consumer:)
      # to route raw chunks into this parser automatically.
      #
      # @return [Ractor]
      def input
        @ractor
      end

      # Send a raw message directly into the parser (useful for testing).
      def push(msg)
        @ractor.send(msg.freeze)
      end

      # Stop the parser Ractor gracefully.
      def stop
        @ractor.send({ type: :stop }.freeze)
      end
    end
  end
end
