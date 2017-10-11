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

    def get_config(filename)
      execute 'GetConfig', {'Filename' => filename}
    end

    # action_num: *args1, action_value: *args12, cat_action_num: *args2, cat_action_value: *args21, var_action_num: *args3, var_action_value: *args31, value_action_num: *args4, value_action_value: *args41, match_num: *args5, match_value: *args51
      def update_config( action_num:, action_value:, cat_action_num:, cat_action_value:, var_action_num:, var_action_value:, value_action_num:, value_action_value:, match_num:, match_value:,  reload: 'true', srcfilename:, dstfilename:)
        queny = { "srcfilename" => srcfilename, "dstfilename" => dstfilename, "reload" => reload }
        number = action_num.to_i
        params =  action_num.split(",").each_with_index do |a_num, index|
                    if cat_action_value.split(",")[index] == 'newcat'
                      action_hash = {"Action-#{a_num}" => action_value.split(",")[index]}
                      cat_hash = {"Cat-#{cat_action_num.split(",")[index]}" => cat_action_value.split(",")[index]}
                      match_hash = {"Match-#{match_num.split(",")[index]}" => match_value.split(",")[index]}
                      newcat = action_hash.merge(cat_hash).merge(match_hash)
                    elsif cat_action_value.split(",")[index] == 'append'
                      action_hash = {"Action-#{a_num}" => action_value.split(",")[index]}
                      cat_hash = {"Cat-#{cat_action_num.split(",")[index]}" => cat_action_value.split(",")[index]}
                      var_hash = {"Var-#{var_action_num.split(",")[index]}" => var_action_value.split(",")[index]}
                      value_hash = {"Value-#{value_action_num.split(",")[index]}" => value_action_value.split(",")[index]}
                      match_hash = {"Match-#{match_num.split(",")[index]}" => match_value.split(",")[index]}
                      append = action_hash.merge(cat_hash).merge(var_hash).merge(value_hash).merge(match_hash)
                    end
                    newcat.merge(append)
                  end

        execute 'UpdateConfig', queny.merge(params)
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
