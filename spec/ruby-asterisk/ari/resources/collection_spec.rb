# frozen_string_literal: true

require 'ruby-asterisk/ari/client'

RSpec.describe RubyAsterisk::ARI::Resources::Collection do
  let(:client) { instance_double(RubyAsterisk::ARI::Client) }
  let(:resource_class) { RubyAsterisk::ARI::Resources::Channel }

  subject(:collection) { described_class.new(resource_class, '/ari/channels', client) }

  describe '#get' do
    let(:channel_data) { { 'id' => 'channel-123' } }

    before do
      allow(client).to receive(:get).with('/ari/channels/channel-123').and_return(channel_data)
    end

    it 'fetches the resource by id' do
      collection.get('channel-123')
      expect(client).to have_received(:get).with('/ari/channels/channel-123')
    end

    it 'returns the resource wrapped in the correct class' do
      result = collection.get('channel-123')
      expect(result).to be_a(RubyAsterisk::ARI::Resources::Channel)
    end

    it 'passes the client to the resource' do
      result = collection.get('channel-123')
      expect(result.client).to eq(client)
    end

    it 'passes the data to the resource' do
      result = collection.get('channel-123')
      expect(result.data).to eq(channel_data)
    end
  end

  describe '#list' do
    let(:channels_data) { [{ 'id' => 'ch-1' }, { 'id' => 'ch-2' }] }

    before do
      allow(client).to receive(:get).with('/ari/channels', {}).and_return(channels_data)
    end

    it 'fetches the full list of resources' do
      collection.list
      expect(client).to have_received(:get).with('/ari/channels', {})
    end

    it 'returns an array of wrapped resources' do
      result = collection.list
      expect(result).to all(be_a(RubyAsterisk::ARI::Resources::Channel))
    end

    it 'returns the correct number of resources' do
      expect(collection.list.size).to eq(2)
    end

    it 'accepts query params' do
      allow(client).to receive(:get).with('/ari/channels', { state: 'Up' }).and_return(channels_data)
      collection.list({ state: 'Up' })
      expect(client).to have_received(:get).with('/ari/channels', { state: 'Up' })
    end
  end
end
