# frozen_string_literal: true

require 'ruby-asterisk/version'
require 'ruby-asterisk/request'
require 'ruby-asterisk/response'
require 'ruby-asterisk/response_builder'
require 'net/telnet'

module RubyAsterisk
  module AMI
    ##
    #
    # Ruby-asterisk main classes
    #
    class Client
      attr_accessor :host, :port, :connected, :timeout, :wait_time

      def initialize(host:, port:)
        self.host = host.to_s
        self.port = port.to_i
        self.connected = false
        @timeout = 5
        @wait_time = 0.1
        @session = nil
      end

      def connect
        @session = Net::Telnet.new('Host' => host, 'Port' => port, 'Timeout' => 10)
        self.connected = true
      rescue StandardError
        false
      end

      def disconnect
        @session.close if connected
        self.connected = false
        true
      rescue StandardError => e
        puts e
        false
      end

      def login(username:, secret:)
        connect unless connected
        execute 'Login', { 'Username' => username, 'Secret' => secret, 'Event' => 'On' }
      end

      def logoff
        execute 'Logoff'
      end

      def command(command)
        execute 'Command', { 'Command' => command }
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
        execute 'ConfbridgeList', { 'Conference' => conference }
      end

      def confbridge_mute(conference:, channel:)
        execute 'ConfbridgeMute', { 'Conference' => conference, 'Channel' => channel }
      end

      def confbridge_unmute(conference:, channel:)
        execute 'ConfbridgeUnmute', { 'Conference' => conference, 'Channel' => channel }
      end

      def confbridge_kick(conference:, channel:)
        execute 'ConfbridgeKick', { 'Conference' => conference, 'Channel' => channel }
      end

      def parked_calls
        execute 'ParkedCalls'
      end

      def extension_state(exten:, context:, action_id: nil)
        execute 'ExtensionState', { 'Exten' => exten, 'Context' => context, 'ActionID' => action_id }
      end

      def device_state_list
        execute 'DeviceStateList'
      end

      def skinny_devices
        execute 'SKINNYdevices'
      end

      def skinny_lines
        execute 'SKINNYlines'
      end

      def status(channel: nil, action_id: nil)
        execute 'Status', { 'Channel' => channel, 'ActionID' => action_id }
      end

      def originate(channel, context, callee, priority, variable: nil, caller_id: nil, timeout: 30_000, async: nil)
        @timeout = [@timeout, timeout / 1000].max
        execute 'Originate',
                { 'Channel' => channel, 'Context' => context, 'Exten' => callee, 'Priority' => priority,
                  'CallerID' => caller_id || channel, 'Timeout' => timeout.to_s, 'Variable' => variable,
                  'Async' => async }
      end

      def originate_app(channel:, application:, data:, async:)
        execute 'Originate',
                { 'Channel' => channel, 'Application' => application, 'Data' => data, 'Timeout' => '30000', 'Async' => async }
      end

      def channels
        execute 'Command', { 'Command' => 'show channels' }
      end

      def redirect(channel, context, callee, priority, variable: nil, caller_id: nil, timeout: 30_000)
        @timeout = [@timeout, timeout / 1000].max
        execute 'Redirect',
                { 'Channel' => channel, 'Context' => context, 'Exten' => callee, 'Priority' => priority,
                  'CallerID' => caller_id || channel, 'Timeout' => timeout.to_s, 'Variable' => variable }
      end

      def queues
        execute 'Queues', {}
      end

      def queue_add(queue, interface, penalty: 2, paused: false, member_name: '')
        execute 'QueueAdd',
                { 'Queue' => queue, 'Interface' => interface, 'Penalty' => penalty, 'Paused' => paused,
                  'MemberName' => member_name }
      end

      def queue_remove(queue:, interface:)
        execute 'QueueRemove', { 'Queue' => queue, 'Interface' => interface }
      end

      def queue_status
        execute 'QueueStatus'
      end

      def queue_summary(queue)
        execute 'QueueSummary', { 'Queue' => queue }
      end

      def mailbox_status(mailbox:, context: 'default')
        execute 'MailboxStatus', { 'Mailbox' => "#{mailbox}@#{context}" }
      end

      def mailbox_count(mailbox:, context: 'default')
        execute 'MailboxCount', { 'Mailbox' => "#{mailbox}@#{context}" }
      end

      def queue_pause(interface:, paused:, queue:, reason: 'none')
        execute 'QueuePause', { 'Interface' => interface, 'Paused' => paused, 'Queue' => queue, 'Reason' => reason }
      end

      def ping
        execute 'Ping'
      end

      def event_mask(event_mask = 'off')
        execute 'Events', { 'EventMask' => event_mask }
      end

      def sip_peers
        execute 'SIPpeers'
      end

      def sip_show_peer(peer)
        execute 'SIPshowpeer', { 'Peer' => peer }
      end

      def hangup(channel)
        execute 'Hangup', { 'Channel' => channel }
      end

      def atxfer(channel:, exten:, context:, priority: '1')
        execute 'Atxfer', { 'Channel' => channel, 'Exten' => exten.to_s, 'Context' => context, 'Priority' => priority }
      end

      def wait_event(timeout: -1)
        @timeout = [@timeout, timeout].max
        execute 'WaitEvent', { 'Timeout' => timeout }
      end

      def monitor(channel, mix: false, file: nil, format: 'wav')
        execute 'Monitor', { 'Channel' => channel, 'File' => file, 'Mix' => mix, 'Format' => format }
      end

      def stop_monitor(channel)
        execute 'StopMonitor', { 'Channel' => channel }
      end

      def pause_monitor(channel)
        execute 'PauseMonitor', { 'Channel' => channel }
      end

      def unpause_monitor(channel)
        execute 'UnpauseMonitor', { 'Channel' => channel }
      end

      def change_monitor(channel:, file:)
        execute 'ChangeMonitor', { 'Channel' => channel, 'File' => file }
      end

      def sip_show_registry
        execute 'SIPshowregistry'
      end

      private

      def execute(command, options = {})
        request = Request.new(command, options)
        request.commands.each do |cmd|
          @session.write(cmd)
        end
        response_data = +''
        @session.waitfor('Match' => /ActionID: #{request.action_id}.*?

/m, 'Timeout' => @timeout,
                         'Waittime' => @wait_time) do |data|
          response_data << data.to_s
        end
        builder = ResponseBuilder.new
        builder.type = command
        builder.raw_response = response_data
        builder.build
      end
    end
  end
end
