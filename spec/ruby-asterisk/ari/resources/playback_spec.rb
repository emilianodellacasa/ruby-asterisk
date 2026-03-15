# frozen_string_literal: true

require 'ruby-asterisk/ari/client'

RSpec.describe RubyAsterisk::ARI::Resources::Playback do
  let(:client) { instance_double(RubyAsterisk::ARI::Client) }
  let(:data) { { 'id' => 'playback-789' } }

  subject(:playback) { described_class.new(data, client) }

  describe '#id' do
    it 'returns the playback id from data' do
      expect(playback.id).to eq('playback-789')
    end
  end

  describe '#stop' do
    it 'deletes the playback' do
      allow(client).to receive(:delete).with('/ari/playbacks/playback-789').and_return(nil)
      playback.stop
      expect(client).to have_received(:delete).with('/ari/playbacks/playback-789')
    end
  end

  describe '#control' do
    it 'posts the operation to the control endpoint' do
      body = { operation: 'pause' }
      allow(client).to receive(:post).with('/ari/playbacks/playback-789/control', body).and_return(nil)
      playback.control('pause')
      expect(client).to have_received(:post).with('/ari/playbacks/playback-789/control', body)
    end
  end
end
