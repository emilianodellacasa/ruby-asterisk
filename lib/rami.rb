require "rami/version"
require 'net/telnet'

module Rami
	class Rami
		attr_accessor :host, :port, :connected

		def initialize(host,port)
			self.host = host.to_s
			self.port = port.to_i
			self.connected = false
			@session = nil
		end

		def connect
			begin
				@session = Net::Telnet::new("Host" => self.host,"Port" => self.port)
				self.connected = true
			rescue Exception => ex
				false
			end
		end

		def disconnect
      begin
        @session.close if self.connected
				@session = nil
				self.connected = false
				true
      rescue Exception => ex
				puts ex
        false
      end
    end

		def login(username,password)
			self.connect unless self.connected
			response_data = ""	
			request = Request.new("Login",{"Username" => username, "Secret" => password})
			request.commands.each do |command|
				@session.write(command)
			end
			@session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 3) do |data|
				response_data << data
			end
			Response.new(response_data)
		end
	end

	class Request
		attr_accessor :action, :action_id, :parameters

		def initialize(action,parameters)
			self.action = action
			self.action_id = self.generate_action_id
			self.parameters = parameters
		end

		def commands
			_commands=["Action: "+self.action+"\r\n","ActionID: "+self.action_id+"\r\n"]
			self.parameters.each do |key,value|
				_commands<<key+": "+value+"\r\n"
			end
			_commands[_commands.length-1]<<"\r\n"
			_commands
		end 

		protected

		def generate_action_id
			Random.rand(999).to_s
		end

	end

	class Response
		attr_accessor :success, :action_id, :message
		
		def initialize(data)
			self.success = self._parse_successfull(data)
			self.action_id = self._parse_action_id(data)
			self.message = self._parse_message(data)
		end

		protected

		def _parse_successfull(data)
			data.include?("Response: Success")
		end

		def _parse_action_id(data)
			_action_id = self._parse(data,"ActionID:")
		end

		def _parse_message(data)
			_message = self._parse(data,"Message:")
		end

		def _parse(data,field)
			_value = nil
			data.each_line do |line|
        if line.start_with?(field)
          _value = line[line.rindex(":")+1..line.size].strip
        end
      end
			_value
		end
	end
end
