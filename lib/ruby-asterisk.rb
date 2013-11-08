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
        self.connected = false
        true
      rescue Exception => ex
        puts ex
        false
      end
    end

    def login(username,password)
      self.connect unless self.connected
      execute "Login", {"Username" => username, "Secret" => password, "Event" => "On"}
    end

    def command(command)
      execute "Command", {"Command" => command}
    end

    def core_show_channels
      execute "CoreShowChannels"
    end

    def meet_me_list
      execute "MeetMeList"
    end

    def parked_calls
      execute "ParkedCalls"
    end

    def extension_state(exten, context, action_id=nil)
      execute "ExtensionState", {"Exten" => exten, "Context" => context, "ActionID" => action_id}
    end

    def skinny_devices
      execute "SKINNYdevices"
    end
    
    def skinny_lines
      execute "SKINNYlines"
    end

    def status(channel=nil,action_id=nil)
      execute "Status", {"Channel" => channel, "ActionID" => action_id}
    end

    def originate(caller,context,callee,priority,variable=nil)
      execute "Originate", {"Channel" => caller, "Context" => context, "Exten" => callee, "Priority" => priority, "Callerid" => caller, "Timeout" => "30000", "Variable" => variable  }
    end

    def channels
      execute "Command", { "Command" => "show channels" }
    end

    def redirect(caller,context,callee,priority,variable=nil)
      execute "Redirect", {"Channel" => caller, "Context" => context, "Exten" => callee, "Priority" => priority, "Callerid" => caller, "Timeout" => "30000", "Variable" => variable}
    end

    def queues
      execute "Queues", {}
    end

    def queue_add(queue, exten, penalty = 2, paused = false, member_name = '')
      execute "QueueAdd", {"Queue" => queue, "Interface" => exten, "Penalty" => penalty, "Paused" => paused, "MemberName" => member_name}
    end

    def queue_pause(exten, paused)
      execute "QueuePause", {"Interface" => exten, "Paused" => paused}
    end

    def queue_remove(queue, exten)
      execute "QueueRemove", {"Queue" => queue, "Interface" => exten}
    end

    def queue_status
      execute "QueueStatus"
    end

    def queue_summary(queue)
      execute "QueueSummary", {"Queue" => queue}
    end

    def mailbox_status(exten, context="default")
      execute "MailboxStatus", {"Mailbox" => "#{exten}@#{context}"}
    end

    def mailbox_count(exten, context="default")
      execute "MailboxCount", {"Mailbox" => "#{exten}@#{context}"}
    end

    def queue_pause(interface,paused,queue,reason='none')
      execute "QueuePause", {"Interface" => interface, "Paused" => paused, "Queue" => queue, "Reason" => reason}
    end

    def ping
      execute "Ping"
    end

    def event_mask(event_mask="off")
      execute "Events", {"EventMask" => event_mask}
    end

    def sip_peers
      execute "SIPpeers"
    end

    private
    def execute(command, options={})
      request = Request.new(command, options)
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor("Match" => /ActionID: #{request.action_id}.*?\n\n/m, "Timeout" => 10) do |data|
        request.response_data << data
      end
      Response.new(command,request.response_data)
    end
  end
end
