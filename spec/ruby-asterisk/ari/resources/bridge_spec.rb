# frozen_string_literal: true

require 'ruby-asterisk/ari/client'

RSpec.describe RubyAsterisk::ARI::Resources::Bridge do
  let(:client) { instance_double(RubyAsterisk::ARI::Client) }
  let(:data) { { 'id' => 'bridge-456' } }

  subject(:bridge) { described_class.new(data, client) }

  describe '#id' do
    it 'returns the bridge id from data' do
      expect(bridge.id).to eq('bridge-456')
    end
  end

  describe '#add_channel' do
    it 'posts to the addChannel endpoint with the channel id' do
      body = { channel: 'channel-123' }
      allow(client).to receive(:post).with('/ari/bridges/bridge-456/addChannel', body).and_return(nil)
      bridge.add_channel('channel-123')
      expect(client).to have_received(:post).with('/ari/bridges/bridge-456/addChannel', body)
    end
  end

  describe '#remove_channel' do
    it 'posts to the removeChannel endpoint with the channel id' do
      body = { channel: 'channel-123' }
      allow(client).to receive(:post).with('/ari/bridges/bridge-456/removeChannel', body).and_return(nil)
      bridge.remove_channel('channel-123')
      expect(client).to have_received(:post).with('/ari/bridges/bridge-456/removeChannel', body)
    end
  end

  describe '#destroy' do
    it 'deletes the bridge' do
      allow(client).to receive(:delete).with('/ari/bridges/bridge-456').and_return(nil)
      bridge.destroy
      expect(client).to have_received(:delete).with('/ari/bridges/bridge-456')
    end
  end
end
