# frozen_string_literal: true

module RubyAsterisk
  ##
  #
  # Class responsible of building commands structure
  #
  class Request
    attr_accessor :action, :action_id, :parameters, :response_data

    def initialize(action, parameters = {})
      self.action = action
      self.action_id = Request.generate_action_id
      self.parameters = parameters
      self.response_data = +''
    end

    def commands
      command_list = ["Action: #{action}\r\n", "ActionID: #{action_id}\r\n"]
      parameters.each do |key, value|
        command_list << "#{key}: #{value}\r\n" unless value.nil?
      end
      command_list[-1] << "\r\n"
      command_list
    end

    def self.generate_action_id
      Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond).to_s(36)
    end
  end
end
