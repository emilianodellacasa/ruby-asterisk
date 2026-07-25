# frozen_string_literal: true

module RubyAsterisk
  module AMI
    # Frame-dispatch and EventList aggregation logic for {Reactor}.
    #
    # AMI list actions reply with an ack frame (Response: Success / EventList:
    # start), one Event frame per item, then a terminating *Complete event —
    # each a separate \r\n\r\n frame carrying the same ActionID. These methods
    # buffer the follow-up events by ActionID and resolve the promise only once
    # the Complete event arrives, so the full frame set reaches ResponseParser.
    #
    # Expects the includer to provide @promises, @promises_mutex, @buffers,
    # @on_event and #resolve_promise.
    module EventListAggregation
      private

      def dispatch(msg)
        case msg[:type]
        when :response
          handle_response(msg[:action_id], msg[:headers], msg[:raw])
        when :event
          handle_event(msg[:event])
        end
      end

      # A response frame either completes a single-reply command immediately or,
      # when it opens an EventList, begins buffering the follow-up Event frames.
      def handle_response(action_id, headers, raw)
        if list_start?(headers)
          start_buffer(action_id, raw)
        else
          resolve_promise(action_id, raw)
        end
      end

      # Event frames carrying the ActionID of a buffering command are appended to
      # that command's reply; the terminating Complete event resolves the promise
      # with the full concatenated frame set. All other events go to on_event.
      def handle_event(event)
        action_id = event.headers['ActionID']
        result = append_to_buffer(action_id, event.raw)
        case result
        when :buffered
          nil # keep accumulating until the Complete event
        when nil
          @on_event&.call(event)
        else # completed: joined raw frames
          resolve_promise(action_id, result)
        end
      end

      def start_buffer(action_id, raw)
        @promises_mutex.synchronize do
          @buffers[action_id] = [raw] if @promises.key?(action_id)
        end
      end

      # Returns :buffered while accumulating, the joined raw when the list is
      # complete, or nil when action_id has no active buffer.
      def append_to_buffer(action_id, raw)
        @promises_mutex.synchronize do
          buffer = @buffers[action_id]
          return nil unless buffer

          buffer << raw
          return :buffered unless list_terminator?(raw)

          @buffers.delete(action_id).join
        end
      end

      def list_start?(headers)
        headers && headers['EventList'].to_s.casecmp?('start')
      end

      def list_terminator?(raw)
        raw.match?(/^EventList:\s*Complete/i) || raw.match?(/^Event:.*Complete\s*$/)
      end
    end
  end
end
