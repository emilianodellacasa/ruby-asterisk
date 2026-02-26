# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/ami/client'
require 'support/mock_ami_server'

# Constant to avoid CollectionLiteralInLoop
NEWLINES = ["\r\n", "\n"].freeze

RSpec.describe RubyAsterisk::AMI::Client do
  let(:mock_server_thread) { nil }
  let(:mock_port) { 0 }

  def flush_mailbox
    Timeout.timeout(0.1) { loop { Ractor.receive } }
  rescue StandardError
    nil
  end

  before do
    flush_mailbox
    # Start server that responds to Login and Ping
    @server_thread, @port = MockAMIServer.start do |client|
      buffer = +''
      while (line = client.gets)
        buffer << line
        next unless NEWLINES.include?(line)

        # Request complete
        if buffer =~ /ActionID: (.*?)\s/
          action_id = Regexp.last_match(1)
          if buffer.include?('Action: Login')
            client.print "Response: Success\r\nActionID: #{action_id}\r\nMessage: Authentication accepted\r\n\r\n"
          elsif buffer.include?('Action: Ping')
            client.print "Response: Success\r\nActionID: #{action_id}\r\nPing: Pong\r\n\r\n"
          end
        end
        buffer.clear
      end
    end
  end

  after do
    @server_thread&.kill
    flush_mailbox
  end

  let(:client) { described_class.new(host: 'localhost', port: @port) }

  describe '#connect' do
    it 'connects successfully' do
      expect(client.connect).to be true
      expect(client.connected).to be true
      client.disconnect
    end
  end

  describe '#login' do
    it 'logs in successfully' do
      expect(client.login(username: 'admin', secret: 'secret')).to be_truthy
      client.disconnect
    end
  end

  describe '#ping' do
    it 'sends ping and receives pong' do
      client.connect
      response = client.ping
      expect(response).not_to be_nil
      client.disconnect
    end
  end
end
