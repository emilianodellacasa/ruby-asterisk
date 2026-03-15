# frozen_string_literal: true

require 'ruby-asterisk/error'
require 'ruby-asterisk/ari/client'

RSpec.describe RubyAsterisk::ARI::Client do
  let(:base_url) { 'http://localhost:8088' }
  let(:api_key) { 'asterisk_api_key' }
  let(:app_name) { 'stasis_app' }

  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_conn) do
    Faraday.new do |conn|
      conn.adapter :test, stubs
    end
  end

  subject(:client) { described_class.new(base_url, api_key, app_name) }

  before do
    client.instance_variable_set(:@connection, test_conn)
  end

  describe '#initialize' do
    it 'stores base_url' do
      expect(client.base_url).to eq(base_url)
    end

    it 'stores app_name' do
      expect(client.app_name).to eq(app_name)
    end
  end

  describe '#get' do
    context 'when the request succeeds' do
      before do
        stubs.get('/ari/channels') do
          [200, { 'Content-Type' => 'application/json' }, '[{"id":"12345"}]']
        end
      end

      it 'returns parsed JSON' do
        result = client.get('/ari/channels')
        expect(result).to eq([{ 'id' => '12345' }])
      end
    end

    context 'when the server returns 404' do
      before do
        stubs.get('/ari/channels/missing') do
          [404, { 'Content-Type' => 'application/json' }, '{"message":"Channel not found"}']
        end
      end

      it 'raises RubyAsterisk::Error' do
        expect { client.get('/ari/channels/missing') }.to raise_error(RubyAsterisk::Error)
      end
    end

    context 'when the server returns 500' do
      before do
        stubs.get('/ari/channels') do
          [500, { 'Content-Type' => 'application/json' }, '{"message":"Internal Server Error"}']
        end
      end

      it 'raises RubyAsterisk::Error' do
        expect { client.get('/ari/channels') }.to raise_error(RubyAsterisk::Error)
      end
    end
  end

  describe '#post' do
    context 'when the request succeeds' do
      before do
        stubs.post('/ari/channels') do
          [200, { 'Content-Type' => 'application/json' }, '{"id":"new_channel"}']
        end
      end

      it 'returns parsed JSON' do
        result = client.post('/ari/channels', { endpoint: 'SIP/alice' })
        expect(result).to eq({ 'id' => 'new_channel' })
      end
    end

    context 'when the server returns 400' do
      before do
        stubs.post('/ari/channels') do
          [400, { 'Content-Type' => 'application/json' }, '{"message":"Missing parameter"}']
        end
      end

      it 'raises RubyAsterisk::Error with the server message' do
        expect { client.post('/ari/channels', {}) }.to raise_error(RubyAsterisk::Error, 'Missing parameter')
      end
    end
  end

  describe '#delete' do
    context 'when the request succeeds' do
      before do
        stubs.delete('/ari/channels/12345') do
          [204, {}, '']
        end
      end

      it 'returns nil for an empty body' do
        result = client.delete('/ari/channels/12345')
        expect(result).to be_nil
      end
    end

    context 'when the server returns 404' do
      before do
        stubs.delete('/ari/channels/missing') do
          [404, { 'Content-Type' => 'application/json' }, '{"message":"Channel not found"}']
        end
      end

      it 'raises RubyAsterisk::Error' do
        expect { client.delete('/ari/channels/missing') }.to raise_error(RubyAsterisk::Error)
      end
    end
  end

  describe '#asterisk_info' do
    let(:info_payload) do
      { 'build' => { 'os' => 'Linux' }, 'system' => { 'entity_id' => 'asterisk' } }.to_json
    end

    before do
      stubs.get('/ari/asterisk/info') do
        [200, { 'Content-Type' => 'application/json' }, info_payload]
      end
    end

    it 'performs GET /ari/asterisk/info and returns parsed data' do
      result = client.asterisk_info
      expect(result).to be_a(Hash)
      expect(result).to have_key('build')
    end
  end
end
