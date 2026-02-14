# frozen_string_literal: true

require 'ruby-asterisk/response_parser'

module RubyAsterisk
  ##
  #
  # Class for response coming from Asterisk
  #
  class Response
    attr_reader :type, :action_id, :message, :data, :raw_response

    def initialize(type, response)
      @raw_response = [response].flatten
      @type = type
      @action_id = _parse_action_id
      @message = _parse_message
      @data = _parse_response
      deep_freeze
      freeze
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

    private

    def deep_freeze
      @type.freeze
      @action_id.freeze
      @message.freeze
      deep_freeze_value(@raw_response)
      deep_freeze_value(@data)
    end

    def deep_freeze_value(obj)
      case obj
      when Hash
        obj.each do |key, value|
          key.freeze
          deep_freeze_value(value)
        end
      when Array
        obj.each { |element| deep_freeze_value(element) }
      end
      obj.freeze
    end
  end
end
