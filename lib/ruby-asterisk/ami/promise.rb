# frozen_string_literal: true

require 'timeout'
require 'ruby-asterisk/response_builder'

module RubyAsterisk
  module AMI
    ##
    # Thread-safe promise representing a pending AMI command response.
    #
    # Created by {Client#execute} and resolved by the event-loop thread
    # when the matching ActionID response arrives from Asterisk.
    #
    # Usage (blocking):
    #   promise = client.ping
    #   response = promise.value(5)   # blocks up to 5 s, returns a Response
    #
    # Usage (async):
    #   promise = client.ping         # returns immediately
    #   # ... do other work ...
    #   response = promise.value      # blocks until resolved or timeout
    #
    class Promise
      attr_reader :action_id

      # Optional callback invoked when {#value} gives up on a timeout, used by
      # the Reactor to drop the abandoned entry from its pending map.
      attr_accessor :on_timeout

      # @param action_id    [String]  the AMI ActionID this promise tracks
      # @param command_type [String]  the AMI action name (e.g. 'Ping')
      # @param timeout      [Numeric] default seconds to wait in #value
      def initialize(action_id:, command_type:, timeout: 5)
        @action_id    = action_id
        @command_type = command_type
        @timeout      = timeout
        @mutex        = Mutex.new
        @cv           = ConditionVariable.new
        @raw          = nil
        @error        = nil
        @resolved     = false
        @on_timeout   = nil
      end

      # Resolve the promise with raw AMI response data.
      # Called by the Client event-loop thread — safe to call from any thread.
      #
      # @param raw [String] the raw AMI response string
      def resolve(raw)
        @mutex.synchronize do
          @raw      = raw
          @resolved = true
          @cv.broadcast
        end
      end

      # Reject the promise with an error.
      # Called when the connection drops or the client disconnects.
      #
      # @param error [Exception]
      def reject(error)
        @mutex.synchronize do
          @error    = error
          @resolved = true
          @cv.broadcast
        end
      end

      # Block until the response arrives and return it as a {Response}.
      #
      # @param timeout [Numeric] seconds to wait (defaults to the value set at construction)
      # @return [RubyAsterisk::Response]
      # @raise [Timeout::Error]  if no response arrives within +timeout+ seconds
      # @raise [RuntimeError]   if the promise was rejected (e.g. disconnect)
      def value(timeout = @timeout)
        @mutex.synchronize do
          unless @resolved
            @cv.wait(@mutex, timeout)
            unless @resolved
              @on_timeout&.call
              raise Timeout::Error,
                    "Timeout waiting for AMI response (ActionID: #{@action_id})"
            end
          end
          raise @error if @error

          build_response
        end
      end

      # @return [Boolean] true if the promise has been resolved or rejected
      def resolved?
        @mutex.synchronize { @resolved }
      end

      private

      def build_response
        ResponseBuilder.new.tap do |builder|
          builder.type         = @command_type
          builder.raw_response = @raw
        end.build
      end
    end
  end
end
