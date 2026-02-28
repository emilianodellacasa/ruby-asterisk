# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/ami/socket_reader_ractor'
require 'support/mock_ami_server'

RSpec.describe RubyAsterisk::SocketReaderRactor do
  let(:mock_server_thread) { nil }
  let(:mock_port) { 0 }

  def flush_mailbox
    Timeout.timeout(0.1) { loop { Ractor.receive } }
  rescue StandardError
    nil
  end

  before do
    flush_mailbox
    @server_thread, @port = MockAMIServer.start
  end

  after do
    begin
      @reader&.stop
    rescue StandardError
      nil
    end
    @server_thread&.kill
    flush_mailbox
  end

  describe '#write' do
    it 'sends data to the server' do
      received_data = Queue.new

      # Restart server with custom handler
      @server_thread.kill
      @server_thread, @port = MockAMIServer.start do |client|
        while (line = client.gets)
          received_data.push(line.chomp)
        end
      end

      @reader = described_class.new('localhost', @port)
      @reader.start

      msg = @reader.take
      expect(msg[:type]).to eq(:connected)

      @reader.write("Test Command\n")

      received = Timeout.timeout(2) { received_data.pop }
      expect(received).to eq('Test Command')
    end
  end
end
