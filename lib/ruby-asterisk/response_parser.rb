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
        raw_response
      end
    end

    protected

    def self._add_status(exten_array)
      exten_array.each do |hint|
        hint["DescriptiveStatus"] = DESCRIPTIVE_STATUS[hint["Status"]]
      end
      exten_array
    end

    def self._parse_objects(response, parse_params)
      object_array = []
      object_regex = Regexp.new(/#{parse_params[:search_for]}\n(.*)\n\n/m)
      object_regex.match(response) do |m|
        object = {}
        lines = m[0].split(/\n/)
        lines.each do |line|
          tokens = line.split(':', 2)
          object[tokens[0].strip]=tokens[1].strip unless tokens[1].nil?
        end
        object_array << object unless object.empty?
      end
      object_array = _add_status(object_array) if parse_params[:symbol].eql?(:hints)
      { parse_params[:symbol] => object_array }
    end
  end
end
