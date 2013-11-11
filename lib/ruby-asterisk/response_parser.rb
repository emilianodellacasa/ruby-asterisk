require 'ruby-asterisk/parsing_constants'

module RubyAsterisk
  ##
  #
  # Class for parsing response coming from Asterisk
  #
  class ResponseParser

    def self.parse(raw_response, type)
      if PARSE_DATA.include?(type)
        self._parse_objects(raw_response, PARSE_DATA[type])
      else
        self.raw_response
      end
    end

    protected

    def self._convert_status(_data)
      _data[:hints].each do |hint|
        hint["DescriptiveStatus"] = DESCRIPTIVE_STATUS[hint["Status"]]
      end
      _data
    end

    def self._parse_objects(response, parse_params)
       _data = { parse_params[:symbol] => [] }
      parsing = false
      object = nil
      response.each_line do |line|
        line.strip!
        if line.strip.empty? or (!parse_params[:stop_with].nil? and line.start_with?(parse_params[:stop_with]))
          parsing = false
        elsif line.start_with?(parse_params[:search_for])
          _data[parse_params[:symbol]] << object unless object.nil?
          object = {}
          parsing = true
        elsif parsing
          tokens = line.split(':', 2)
          object[tokens[0].strip]=tokens[1].strip unless tokens[1].nil?
        end
      end
      _data[parse_params[:symbol]] << object unless object.nil?
      _data = _convert_status(_data) if _data.include?(:hints)
      _data
    end
  end
end
