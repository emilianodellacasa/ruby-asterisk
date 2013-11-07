require "ruby-asterisk/version"
require "ruby-asterisk/request"
require "ruby-asterisk/response"

require 'net/telnet'

module RubyAsterisk
  class AMI
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
      request = Request.new("Login",{"Username" => username, "Secret" => password})
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("Login",request.response_data)
    end

    def command(command)
      request = Request.new("Command",{ "Command" => command })
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "--END COMMAND--\n\n", "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("Command",request.response_data)
    end

    def core_show_channels
      request = Request.new("CoreShowChannels")
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: #{request.action_id}\n\n", "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("CoreShowChannels",request.response_data)
    end

    def meet_me_list
      request = Request.new("MeetMeList")
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("MeetMeList",request.response_data)
    end

    def parked_calls
      request = Request.new("ParkedCalls")
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("ParkedCalls",request.response_data)
    end

    def extension_state(exten, context, action_id=nil)
      request = Request.new("ExtensionState",{"Exten" => exten, "Context" => context, "ActionID" => action_id})
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("ExtensionState",request.response_data)
    end

    def skinny_devices
      request = Request.new("SKINNYdevices")
      request.commands.each do |c|
        @session.write(c)
      end
      @session.waitfor("Match" => /ActionID: #{request.action_id}\n\n/, "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("SKINNYdevices",request.response_data)
    end
    
    def skinny_lines
      request = Request.new("SKINNYlines")
      request.commands.each do |c|
        @session.write(c)
      end
      @session.waitfor("Match" => /ActionID: #{request.action_id}\n\n/, "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("SKINNYlines",request.response_data)
    end

    def status(channel=nil,action_id=nil)
      request = Request.new("Status",{"Channel" => channel, "ActionID" => action_id})
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 3) do |data|
        request.response_data << data
      end
      Response.new("Status",request.response_data)
    end

    def originate(caller,context,callee,priority,variable=nil)
      request = Request.new("Originate",{"Channel" => caller, "Context" => context, "Exten" => callee, "Priority" => priority, "Callerid" => caller, "Timeout" => "30000", "Variable" => variable  })
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 40) do |data|
        request.response_data << data
      end
      Response.new("Originate",request.response_data)
    end

    def queue_pause(interface,paused,queue,reason='none')
      request = Request.new("QueuePause",{"Interface" => interface, "Paused" => paused, "Queue" => queue, "Reason" => reason})
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 40) do |data|
        request.response_data << data
      end
      Response.new("QueuePause",request.response_data)
    end

    def ping
      request = Request.new("Ping")
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 60) do |data|
        request.response_data << data
      end
      Response.new("Ping", request.response_data)
    end

    def event_mask(event_mask="off")
      request = Request.new("Events", {"EventMask" => event_mask})
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 60) do |data|
        request.response_data << data
      end
      Response.new("Events", request.response_data)

    end

    def sip_peers
      request = Request.new("SIPpeers")
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("String" => "ActionID: "+request.action_id, "Timeout" => 60) do |data|
        request.response_data << data                                                                                   
      end
      Response.new("SIPpeers", request.response_data)                                                                       end
  end
end
