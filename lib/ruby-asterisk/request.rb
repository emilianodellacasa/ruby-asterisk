# frozen_string_literal: true

module RubyAsterisk
  ##
  #
  # Class responsible of building commands structure
  #
  class Request
    attr_reader :action, :action_id, :parameters

    def initialize(action, parameters = {})
      @action = action.freeze
      @action_id = Request.generate_action_id.freeze
      @parameters = deep_freeze_hash(parameters)
      freeze
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

    private

    def deep_freeze_hash(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.freeze] = value.freeze
      end.freeze
    end
  end
end
