require "rami/version"
require "rami/request"
require "rami/response"

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
				request.response_data << data
			end
			Response.new("Login",request.response_data)
		end

		def core_show_channels
			response_data = ""
      request = Request.new("CoreShowChannels")
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("CoreShowChannels",request.response_data)
		end
	end
end
