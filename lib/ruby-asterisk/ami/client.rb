# frozen_string_literal: true

require 'ruby-asterisk/version'
require 'ruby-asterisk/request'
require 'ruby-asterisk/response'
require 'ruby-asterisk/response_builder'
require 'ruby-asterisk/ami/commands/system'
require 'ruby-asterisk/ami/commands/channel'
require 'ruby-asterisk/ami/commands/conference'
require 'ruby-asterisk/ami/commands/extension'
require 'ruby-asterisk/ami/commands/queue'
require 'ruby-asterisk/ami/commands/mailbox'
require 'ruby-asterisk/ami/commands/sip'
require 'ruby-asterisk/ami/commands/monitor'
require 'net/telnet'

module RubyAsterisk
  module AMI
    ##
    #
    # Ruby-asterisk main classes
    #
    class Client
      include Commands::System
      include Commands::Channel
      include Commands::Conference
      include Commands::Extension
      include Commands::Queue
      include Commands::Mailbox
      include Commands::Sip
      include Commands::Monitor

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
