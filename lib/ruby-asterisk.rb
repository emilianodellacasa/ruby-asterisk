require 'ruby-asterisk/version'
require 'ruby-asterisk/request'
require 'ruby-asterisk/response'
require 'net/telnet'

module RubyAsterisk
  ##
  #
  # Ruby-asterisk main classes
  #
  class AMI
    attr_accessor :host, :port, :connected, :timeout, :wait_time

    def initialize(host, port)
      self.host = host.to_s
      self.port = port.to_i
      self.connected = false
      @timeout = 5
      @wait_time = 0.1
      @session = nil
    end

    def connect
      begin
        @session = Net::Telnet::new('Host' => self.host, 'Port' => self.port, 'Timeout' => 10)
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

    def login(username, password)
      self.connect unless self.connected
      execute 'Login', {'Username' => username, 'Secret' => password, 'Event' => 'On'}
    end

    def logoff
      execute 'Logoff'
    end

    def command(command)
      execute 'Command', {'Command' => command}
    end

    def core_show_channels
      execute 'CoreShowChannels'
    end

    def meet_me_list
      execute 'MeetMeList'
    end

    def confbridges
      execute 'ConfbridgeListRooms'
    end

    def confbridge(conference)
      execute 'ConfbridgeList', {'Conference' => conference}
    end

    def confbridge_mute(conference, channel)
      execute 'ConfbridgeMute', {'Conference' => conference, 'Channel' => channel}
    end

    def confbridge_unmute(conference, channel)
      execute 'ConfbridgeUnmute', {'Conference' => conference, 'Channel' => channel}
    end

    def confbridge_kick(conference, channel)
      execute 'ConfbridgeKick', {'Conference' => conference, 'Channel' => channel}
    end

    def parked_calls
      execute 'ParkedCalls'
    end

    def extension_state(exten, context, action_id = nil)
      execute 'ExtensionState', {'Exten' => exten, 'Context' => context, 'ActionID' => action_id}
    end

    def skinny_devices
      execute 'SKINNYdevices'
    end

    def skinny_lines
      execute 'SKINNYlines'
    end

    def status(channel = nil, action_id = nil)
      execute 'Status', {'Channel' => channel, 'ActionID' => action_id}
    end

    def originate(channel, context, callee, priority, variable = nil, caller_id = nil, timeout = 30000)
      @timeout = [@timeout, timeout/1000].max
      execute 'Originate', {'Channel' => channel, 'Context' => context, 'Exten' => callee, 'Priority' => priority, 'CallerID' => caller_id || channel, 'Timeout' => timeout.to_s, 'Variable' => variable  }
    end

    def originate_app(caller, app, data, async)
      execute 'Originate', {'Channel' => caller, 'Application' => app, 'Data' => data, 'Timeout' => '30000', 'Async' => async }
    end

    def channels
      execute 'Command', { 'Command' => 'show channels' }
    end

    def redirect(channel, context, callee, priority, variable=nil, caller_id = nil, timeout = 30000)
      @timeout = [@timeout, timeout/1000].max
      execute 'Redirect', {'Channel' => channel, 'Context' => context, 'Exten' => callee, 'Priority' => priority, 'CallerID' => caller_id || channel, 'Timeout' => timeout.to_s, 'Variable' => variable}
    end

    def queues
      execute 'Queues', {}
    end

    def queue_add(queue, exten, penalty = 2, paused = false, member_name = '')
      execute 'QueueAdd', {'Queue' => queue, 'Interface' => exten, 'Penalty' => penalty, 'Paused' => paused, 'MemberName' => member_name}
    end

    def queue_pause(exten, paused)
      execute 'QueuePause', {'Interface' => exten, 'Paused' => paused}
    end

    def queue_remove(queue, exten)
      execute 'QueueRemove', {'Queue' => queue, 'Interface' => exten}
    end

    def queue_status
      execute 'QueueStatus'
    end

    def queue_summary(queue)
      execute 'QueueSummary', {'Queue' => queue}
    end

    def mailbox_status(exten, context='default')
      execute 'MailboxStatus', {'Mailbox' => "#{exten}@#{context}"}
    end

    def mailbox_count(exten, context='default')
      execute 'MailboxCount', {'Mailbox' => "#{exten}@#{context}"}
    end

    def queue_pause(interface,paused,queue,reason='none')
      execute 'QueuePause', {'Interface' => interface, 'Paused' => paused, 'Queue' => queue, 'Reason' => reason}
    end

    def ping
      execute 'Ping'
    end

    def event_mask(event_mask='off')
      execute 'Events', {'EventMask' => event_mask}
    end

    def sip_peers
      execute 'SIPpeers'
    end
    
    def hangup(channel)
      execute 'Hangup', {'Channel' => channel}
    end

    def atxfer(channel, exten, context, priority = '1')
      execute 'Atxfer', {'Channel' => channel, 'Exten' => exten.to_s, 'Context' => context, 'Priority' => priority}
    end

    private
    def execute(command, options = {})
      request = Request.new(command, options)
      request.commands.each do |command|
        @session.write(command)
      end
      @session.waitfor('Match' => /ActionID: #{request.action_id}.*?\n\n/m, "Timeout" => @timeout, "Waittime" => @wait_time) do |data|
        request.response_data << data.to_s
      end
      Response.new(command, request.response_data)
    end
  end
end
