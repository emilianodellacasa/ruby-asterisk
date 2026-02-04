# frozen_string_literal: true

require 'ruby-asterisk/response_parser'

module RubyAsterisk
  ##
  #
  # Class for response coming from Asterisk
  #
  class Response
    attr_accessor :type, :action_id, :message, :data, :raw_response

    def initialize(type, response)
      self.raw_response = [response].flatten
      self.type = type
      self.action_id = _parse_action_id
      self.message = _parse_message
      self.data = _parse_response
    end

    def success
      raw_response.join.include?('Response: Success')
    end

    protected

    def _parse_action_id
      _parse('ActionID:')
    end

    def _parse_message
      _parse('Message:')
    end

    def _parse(field)
      raw_response.each do |data|
        data.each_line do |line|
          return line[(line.rindex(':') + 1)..line.size].strip if line.start_with?(field)
        end
      end
      nil
    end

    def _parse_response
      ResponseParser.parse(raw_response, type)
    end
  end
end
