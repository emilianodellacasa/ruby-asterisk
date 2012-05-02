module RubyAsterisk
	class Request
		attr_accessor :action, :action_id, :parameters, :response_data

		def initialize(action,parameters={})
			self.action = action
			self.action_id = self.generate_action_id
			self.parameters = parameters
			self.response_data = ""
		end

		def commands
			_commands=["Action: "+self.action+"\r\n","ActionID: "+self.action_id+"\r\n"]
			self.parameters.each do |key,value|
				_commands<<key+": "+value+"\r\n" unless value.nil?
			end
			_commands[_commands.length-1]<<"\r\n"
			_commands
		end 

		protected

		def generate_action_id
			Random.rand(999).to_s
		end

	end
end
