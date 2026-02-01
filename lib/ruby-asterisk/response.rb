require 'ruby-asterisk/response_parser'

module RubyAsterisk
  ##
  #
  # Class for response coming from Asterisk
  #
  class Response
    attr_accessor :type, :action_id, :message, :data, :raw_response

    def initialize(type,response)
      self.raw_response = [response].flatten
      self.type = type
      self.action_id = self._parse_action_id
      self.message = self._parse_message
      self.data = self._parse_response
    end

    def success
      self.raw_response.join.include?("Response: Success")
    end

    protected

    def _parse_action_id
      self._parse("ActionID:")
    end

    def _parse_message
      self._parse("Message:")
    end

    def _parse(field)
      self.raw_response.each do |data|
        data.each_line do |line|
          if line.start_with?(field)
            return line[line.rindex(":")+1..line.size].strip
          end
        end
      end
      nil
    end

    def _parse_response
      ResponseParser.parse(self.raw_response, self.type)
    end

  end
end
