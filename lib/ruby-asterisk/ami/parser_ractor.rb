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
      # AMI message delimiter — two consecutive CRLF pairs.
      DELIMITER     = "\r\n\r\n"
      DELIMITER_LEN = DELIMITER.length

      # Defined as a constant Proc so the Ractor block closes over nothing
      # non-shareable.  The `consumer` Ractor is passed as an argument
      # (shareable by definition).
      RACTOR_LOGIC = Proc.new do |consumer|
        buffer = +''

        loop do
          msg = Ractor.receive

          case msg[:type]

          # ── raw data from the socket ──────────────────────────────────────
          when :data
            buffer << msg[:data]

            # Drain all complete messages from the buffer.
            while (idx = buffer.index(DELIMITER))
              raw = buffer.slice!(0, idx + DELIMITER_LEN)

              # Parse every "Key: Value" line; skip unparseable lines (e.g.
              # the AMI welcome banner "Asterisk Call Manager/1.1\n").
              headers = {}
              raw.split(/\r?\n/).each do |line|
                next if line.empty?
                colon = line.index(':')
                next unless colon && colon.positive?

                key   = line[0, colon].freeze
                value = line[colon + 1..].lstrip.rstrip.freeze
                headers[key] = value
              end
              headers.freeze

              next if headers.empty?

              frozen_raw = raw.freeze

              if headers.key?('Response')
                consumer.send(
                  {
                    type:      :response,
                    headers:   headers,
                    raw:       frozen_raw,
                    action_id: headers['ActionID']
                  }.freeze
                )

              elsif headers.key?('Event')
                consumer.send(
                  {
                    type:  :event,
                    event: RubyAsterisk::AMI::Event.new(headers, frozen_raw)
                  }.freeze
                )
              end
              # Messages with neither Response: nor Event: (e.g. bare banner
              # lines that ended up without a proper delimiter) are silently
              # discarded — they carry no actionable data.
            end

          # ── pass-through control messages ─────────────────────────────────
          when :connected, :disconnected, :error
            consumer.send(msg)

          # ── graceful shutdown ──────────────────────────────────────────────
          when :stop
            break
          end
        end
      end

      # @param consumer [Ractor] the Ractor that will receive parsed messages
      #   (typically Ractor.current of the AMI::Client thread).
      def initialize(consumer)
        @ractor = Ractor.new(consumer, &RACTOR_LOGIC)
      end

      ##
      # The underlying Ractor.
      # Pass this to SocketReaderRactor#start(consumer:) so that raw chunks
      # are routed into the parser automatically.
      #
      # @return [Ractor]
      def input
        @ractor
      end

      ##
      # Send a raw message directly into the parser (useful for testing).
      #
      def push(msg)
        @ractor.send(msg.freeze)
      end

      ##
      # Stop the parser Ractor gracefully.
      #
      def stop
        @ractor.send({ type: :stop }.freeze)
      end
    end
  end
end
