# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/ami/client'
require 'support/mock_ami_server'
require 'timeout'

# Regression coverage for AMI EventList (multi-frame) responses. A list action
# replies with an ack frame (EventList: start), then one Event frame per item,
# then a terminating *Complete event — each a separate \r\n\r\n frame carrying
# the same ActionID. The Reactor must aggregate them before resolving so that
# ResponseParser can extract the structured data.
FRAME_NEWLINES = ["\r\n", "\n"].freeze

def list_responder
  lambda do |sock|
    buf = +''
    while (line = sock.gets)
      buf << line
      next unless FRAME_NEWLINES.include?(line)

      if buf.include?('Action: CoreShowChannels') && buf =~ /ActionID: (\S+)/
        id = Regexp.last_match(1)
        sock.print "Response: Success\r\nActionID: #{id}\r\nEventList: start\r\n" \
                   "Message: Channels will follow\r\n\r\n"
        sock.print "Event: CoreShowChannel\r\nActionID: #{id}\r\n" \
                   "Channel: SIP/100-00000001\r\nChannelState: 6\r\n\r\n"
        sock.print "Event: CoreShowChannel\r\nActionID: #{id}\r\n" \
                   "Channel: SIP/200-00000002\r\nChannelState: 6\r\n\r\n"
        sock.print "Event: CoreShowChannelsComplete\r\nActionID: #{id}\r\n" \
                   "EventList: Complete\r\nListItems: 2\r\n\r\n"
      end
      buf.clear
    end
  end
end

RSpec.describe 'RubyAsterisk::AMI::Client — EventList aggregation' do
  before { @server_thread, @port = MockAMIServer.start(&list_responder) }
  after { @server_thread&.kill }

  let(:client) { RubyAsterisk::AMI::Client.new(host: 'localhost', port: @port) }

  it 'aggregates the ack, event, and Complete frames into one Response' do
    client.connect
    response = client.core_show_channels.value(2)

    expect(response).to be_a(RubyAsterisk::Response)
    expect(response.data).to be_a(Hash)
    channels = response.data[:channels]
    expect(channels.size).to eq(2)
    expect(channels.map { |c| c['Channel'] })
      .to contain_exactly('SIP/100-00000001', 'SIP/200-00000002')

    client.disconnect
  end
end
