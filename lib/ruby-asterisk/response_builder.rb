# frozen_string_literal: true

module RubyAsterisk
  ##
  #
  # Mutable builder that produces an immutable Response
  #
  class ResponseBuilder
    attr_accessor :type, :raw_response

    def build
      raise ArgumentError, 'type is required' if @type.nil?
      raise ArgumentError, 'raw_response is required' if @raw_response.nil?

      Response.new(@type, @raw_response)
    end
  end
end
