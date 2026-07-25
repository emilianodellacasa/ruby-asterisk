# frozen_string_literal: true

module RubyAsterisk
  ##
  #
  # Class responsible of building commands structure
  #
  class Request
    attr_reader :action, :action_id, :parameters

    @id_mutex   = Mutex.new
    @id_counter = 0

    # @param action     [String] AMI action name
    # @param parameters [Hash]   additional AMI headers
    # @param action_id  [String, nil] ActionID to use; a generated one when nil.
    #   Passing it here (rather than as a parameter) keeps a single ActionID
    #   header on the wire, so responses still correlate with their Promise.
    def initialize(action, parameters = {}, action_id: nil)
      @action = action.freeze
      @action_id = (action_id || Request.generate_action_id).to_s.freeze
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

    # Monotonic timestamp plus a process-wide atomic counter, so two calls made
    # within the same nanosecond (or across an NTP clock step-back) never collide.
    def self.generate_action_id
      count = @id_mutex.synchronize { @id_counter += 1 }
      "#{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond).to_s(36)}-#{count.to_s(36)}"
    end

    private

    def deep_freeze_hash(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.freeze] = value.freeze
      end.freeze
    end
  end
end
