require 'ruby-asterisk/response_parser'

module RubyAsterisk
  ##
  #
  # Class for response coming from Asterisk
  #
  class Response
    attr_accessor :type, :action_id, :message, :data, :raw_response

    def initialize(type,response)
      self.raw_response = response
      self.type = type
      self.action_id = self._parse_action_id
      self.message = self._parse_message
      self.data = self._parse_response
    end

    def success
      self.raw_response.include?("Response: Success")
    end

    protected

    def _parse_action_id
      self._parse("ActionID:")
    end

    def _parse_message
      self._parse("Message:")
    end

    def _parse(field)
      _value = nil
      self.raw_response.each_line do |line|
        if line.start_with?(field)
          _value = line[line.rindex(":")+1..line.size].strip
        end
      end
      _value
    end

    def _parse_response
      ResponseParser.parse(self.raw_response, self.type)
    end

  end
end
