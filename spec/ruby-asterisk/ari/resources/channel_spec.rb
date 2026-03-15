# frozen_string_literal: true

require 'ruby-asterisk/ari/client'

RSpec.describe RubyAsterisk::ARI::Resources::Channel do
  let(:client) { instance_double(RubyAsterisk::ARI::Client) }
  let(:data) { { 'id' => 'channel-123' } }

  subject(:channel) { described_class.new(data, client) }

  describe '#id' do
    it 'returns the channel id from data' do
      expect(channel.id).to eq('channel-123')
    end
  end

  describe '#ring' do
    it 'posts to the ring endpoint' do
      allow(client).to receive(:post).with('/ari/channels/channel-123/ring').and_return(nil)
      channel.ring
      expect(client).to have_received(:post).with('/ari/channels/channel-123/ring')
    end
  end

  describe '#answer' do
    it 'posts to the answer endpoint' do
      allow(client).to receive(:post).with('/ari/channels/channel-123/answer').and_return(nil)
      channel.answer
      expect(client).to have_received(:post).with('/ari/channels/channel-123/answer')
    end
  end

  describe '#hangup' do
    it 'deletes the channel' do
      allow(client).to receive(:delete).with('/ari/channels/channel-123').and_return(nil)
      channel.hangup
      expect(client).to have_received(:delete).with('/ari/channels/channel-123')
    end
  end

  describe '#play' do
    let(:expected_body) { { media: 'sound:hello-world' } }

    it 'posts to the play endpoint with the media parameter' do
      allow(client).to receive(:post).with('/ari/channels/channel-123/play', expected_body).and_return({})
      channel.play('sound:hello-world')
      expect(client).to have_received(:post).with('/ari/channels/channel-123/play', expected_body)
    end

    it 'merges additional params into the request body' do
      body = { media: 'sound:hello-world', lang: 'en' }
      allow(client).to receive(:post).with('/ari/channels/channel-123/play', body).and_return({})
      channel.play('sound:hello-world', { lang: 'en' })
      expect(client).to have_received(:post).with('/ari/channels/channel-123/play', body)
    end
  end
end
