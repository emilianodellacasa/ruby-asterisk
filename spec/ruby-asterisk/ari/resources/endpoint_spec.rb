# frozen_string_literal: true

require 'ruby-asterisk/ari/client'

RSpec.describe RubyAsterisk::ARI::Resources::Endpoint do
  let(:client) { instance_double(RubyAsterisk::ARI::Client) }
  let(:data) do
    { 'technology' => 'SIP', 'resource' => 'alice', 'state' => 'online' }
  end

  subject(:endpoint) { described_class.new(data, client) }

  describe '#technology' do
    it 'returns the technology from data' do
      expect(endpoint.technology).to eq('SIP')
    end
  end

  describe '#resource' do
    it 'returns the resource from data' do
      expect(endpoint.resource).to eq('alice')
    end
  end

  describe '#state' do
    it 'returns the state from data' do
      expect(endpoint.state).to eq('online')
    end
  end
end
