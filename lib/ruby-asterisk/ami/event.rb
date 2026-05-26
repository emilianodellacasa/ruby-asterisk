# frozen_string_literal: true

module RubyAsterisk
  module AMI
    ##
    # Immutable value object representing a parsed AMI event.
    # All attributes are frozen for thread-safe sharing.
    #
    class Event
      attr_reader :name, :headers, :raw

      # @param headers [Hash] frozen hash of parsed AMI headers (Key => Value strings)
      # @param raw     [String] frozen raw message string including the trailing \r\n\r\n
      def initialize(headers, raw)
        @name    = headers['Event'].freeze
        @headers = headers
        @raw     = raw
        freeze
      end
    end
  end
end
