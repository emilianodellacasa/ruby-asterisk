# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyAsterisk::ARI::WebSocket do
  let(:base_url) { 'http://localhost:8088' }
  let(:api_key) { 'asterisk_api_key' }
  let(:app_name) { 'stasis_app' }
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil) }

  subject(:websocket) { described_class.new(base_url, api_key, app_name, logger: logger) }

  describe '#initialize' do
    it 'sets the base_url' do
      expect(websocket.instance_variable_get(:@base_url)).to eq(base_url)
    end

    it 'sets the app_name' do
      expect(websocket.app_name).to eq(app_name)
    end

    it 'initializes callbacks as empty hash' do
      expect(websocket.callbacks).to eq({})
    end

    it 'sets connected to false' do
      expect(websocket.connected).to be(false)
    end

    it 'sets auto_reconnect to true by default' do
      expect(websocket.instance_variable_get(:@should_reconnect)).to be(true)
    end

    it 'allows disabling auto_reconnect' do
      ws = described_class.new(base_url, api_key, app_name, auto_reconnect: false)
      expect(ws.instance_variable_get(:@should_reconnect)).to be(false)
    end

    it 'uses default ping interval' do
      expect(websocket.instance_variable_get(:@ping_interval)).to eq(described_class::PING_INTERVAL)
    end

    it 'allows custom ping interval' do
      ws = described_class.new(base_url, api_key, app_name, ping_interval: 60)
      expect(ws.instance_variable_get(:@ping_interval)).to eq(60)
    end
  end

  describe '#on' do
    it 'registers a callback for an event type' do
      callback = proc { |data| puts data }
      websocket.on('StasisStart', &callback)

      expect(websocket.callbacks['StasisStart']).to include(callback)
    end

    it 'allows multiple callbacks for the same event' do
      callback1 = proc { |data| puts data }
      callback2 = proc { |data| puts data }

      websocket.on('StasisStart', &callback1)
      websocket.on('StasisStart', &callback2)

      expect(websocket.callbacks['StasisStart']).to include(callback1, callback2)
    end

    it 'converts symbol event types to strings' do
      callback = proc { |data| puts data }
      websocket.on(:StasisStart, &callback)

      expect(websocket.callbacks['StasisStart']).to include(callback)
    end

    it 'returns self for method chaining' do
      result = websocket.on('StasisStart') { |data| puts data }
      expect(result).to eq(websocket)
    end
  end

  describe '#connected?' do
    context 'when not connected' do
      it 'returns false' do
        expect(websocket.connected?).to be(false)
      end
    end

    context 'when connected flag is true but no driver' do
      before do
        websocket.instance_variable_set(:@connected, true)
      end

      it 'returns false' do
        expect(websocket.connected?).to be(false)
      end
    end

    context 'when connected with an open driver' do
      let(:driver) { instance_double(WebSocket::Driver::Client, state: :open) }

      before do
        websocket.instance_variable_set(:@connected, true)
        websocket.instance_variable_set(:@driver, driver)
      end

      it 'returns true' do
        expect(websocket.connected?).to be(true)
      end
    end
  end

  describe '#send_message?' do
    context 'when not connected' do
      it 'returns false' do
        expect(websocket.send_message?('test')).to be(false)
      end
    end

    context 'when connected' do
      let(:driver) { instance_double(WebSocket::Driver::Client, state: :open, text: true) }

      before do
        websocket.instance_variable_set(:@connected, true)
        websocket.instance_variable_set(:@driver, driver)
      end

      it 'sends string message' do
        websocket.send_message?('test message')
        expect(driver).to have_received(:text).with('test message')
      end

      it 'converts hash to JSON' do
        websocket.send_message?({ type: 'test', data: 'value' })
        expect(driver).to have_received(:text).with('{"type":"test","data":"value"}')
      end

      it 'returns true' do
        expect(websocket.send_message?('test')).to be(true)
      end

      it 'returns false when the write raises IOError' do
        allow(driver).to receive(:text).and_raise(IOError)
        expect(websocket.send_message?('test')).to be(false)
      end
    end
  end

  describe '#disconnect' do
    let(:driver) { instance_double(WebSocket::Driver::Client, state: :open, close: nil) }
    let(:socket) { instance_double(TCPSocket, close: nil) }

    before do
      websocket.instance_variable_set(:@driver, driver)
      websocket.instance_variable_set(:@socket, socket)
      websocket.instance_variable_set(:@connected, true)
    end

    it 'sets should_reconnect to false' do
      websocket.disconnect
      expect(websocket.instance_variable_get(:@should_reconnect)).to be(false)
    end

    it 'stops the ping timer' do
      websocket.disconnect
      expect(websocket.instance_variable_get(:@ping_token)).to be_nil
      expect(websocket.instance_variable_get(:@ping_thread)).to be_nil
    end

    it 'sends a close frame' do
      websocket.disconnect
      expect(driver).to have_received(:close)
    end

    it 'closes the socket' do
      websocket.disconnect
      expect(socket).to have_received(:close)
    end

    it 'sets connected to false' do
      websocket.disconnect
      expect(websocket.connected).to be(false)
    end

    it 'logs disconnection' do
      websocket.disconnect
      expect(logger).to have_received(:info).with('WebSocket disconnected')
    end

    it 'returns self' do
      expect(websocket.disconnect).to eq(websocket)
    end
  end

  describe 'private #build_url' do
    it 'builds WebSocket URL with ws scheme for http' do
      url = websocket.send(:build_url)
      expect(url).to eq("ws://#{api_key}:@localhost:8088/ari/events?app=#{app_name}")
    end

    it 'builds WebSocket URL with wss scheme for https' do
      ws = described_class.new('https://localhost:8089', api_key, app_name)
      url = ws.send(:build_url)
      expect(url).to eq("wss://#{api_key}:@localhost:8089/ari/events?app=#{app_name}")
    end

    it 'includes app name in query string' do
      url = websocket.send(:build_url)
      expect(url).to include("app=#{app_name}")
    end
  end

  describe 'private #dispatch_event' do
    let(:event_data) { { 'type' => 'StasisStart', 'channel' => { 'id' => '123' } } }

    it 'calls registered callback for event type' do
      called = false
      received_data = nil

      websocket.on('StasisStart') do |data|
        called = true
        received_data = data
      end

      websocket.send(:dispatch_event, 'StasisStart', event_data)

      expect(called).to be(true)
      expect(received_data).to eq(event_data)
    end

    it 'calls multiple callbacks for the same event' do
      call_count = 0

      websocket.on('StasisStart') { call_count += 1 }
      websocket.on('StasisStart') { call_count += 1 }

      websocket.send(:dispatch_event, 'StasisStart', event_data)

      expect(call_count).to eq(2)
    end

    it 'calls wildcard callbacks for any event' do
      called = false
      received_data = nil

      websocket.on('*') do |data|
        called = true
        received_data = data
      end

      websocket.send(:dispatch_event, 'StasisStart', event_data)

      expect(called).to be(true)
      expect(received_data).to eq(event_data)
    end

    it 'logs errors in callbacks but does not raise' do
      websocket.on('StasisStart') { raise 'Callback error' }

      expect { websocket.send(:dispatch_event, 'StasisStart', event_data) }.not_to raise_error
      expect(logger).to have_received(:error).with(/Error in event handler/)
    end

    it 'does not call callbacks for different event types' do
      called = false
      websocket.on('ChannelHangup') { called = true }

      websocket.send(:dispatch_event, 'StasisStart', event_data)

      expect(called).to be(false)
    end
  end

  describe 'private #handle_message' do
    let(:event_json) { '{"type":"StasisStart","channel":{"id":"123"}}' }
    let(:event) { double('WebSocket::Driver::MessageEvent', data: event_json) }

    it 'parses JSON and dispatches event' do
      called = false
      websocket.on('StasisStart') { called = true }

      websocket.send(:handle_message, event)

      expect(called).to be(true)
    end

    it 'logs received event' do
      websocket.send(:handle_message, event)
      expect(logger).to have_received(:debug).with('Received event: StasisStart')
    end

    it 'logs error for invalid JSON' do
      invalid_event = double('WebSocket::Driver::MessageEvent', data: 'invalid json')

      websocket.send(:handle_message, invalid_event)

      expect(logger).to have_received(:error).with(/Failed to parse message/)
    end
  end

  describe 'private #handle_open' do
    let(:driver) { instance_double(WebSocket::Driver::Client) }
    let(:connect_callback) { proc { |ws| } }

    before do
      websocket.instance_variable_set(:@driver, driver)
      websocket.instance_variable_set(:@on_connect_callback, connect_callback)
      allow(websocket).to receive(:start_ping_timer)
    end

    it 'sets connected to true' do
      websocket.send(:handle_open)
      expect(websocket.connected).to be(true)
    end

    it 'resets reconnect attempts' do
      websocket.instance_variable_set(:@reconnect_attempts, 5)
      websocket.send(:handle_open)
      expect(websocket.instance_variable_get(:@reconnect_attempts)).to eq(0)
    end

    it 'logs successful connection' do
      websocket.send(:handle_open)
      expect(logger).to have_received(:info).with('WebSocket connected successfully')
    end

    it 'starts ping timer' do
      websocket.send(:handle_open)
      expect(websocket).to have_received(:start_ping_timer)
    end

    it 'calls on_connect callback' do
      expect(connect_callback).to receive(:call).with(websocket)
      websocket.send(:handle_open)
    end
  end

  describe 'private #handle_close' do
    let(:event) { double('WebSocket::Driver::CloseEvent', code: 1000, reason: 'Normal closure') }

    before do
      websocket.instance_variable_set(:@connected, true)
      allow(websocket).to receive(:stop_ping_timer)
      allow(websocket).to receive(:close_socket)
    end

    it 'sets connected to false' do
      websocket.send(:handle_close, event)
      expect(websocket.connected).to be(false)
    end

    it 'stops ping timer' do
      websocket.send(:handle_close, event)
      expect(websocket).to have_received(:stop_ping_timer)
    end

    it 'logs close event' do
      websocket.send(:handle_close, event)
      expect(logger).to have_received(:warn).with(/WebSocket closed/)
    end

    it 'closes the socket so the read loop unblocks' do
      websocket.send(:handle_close, event)
      expect(websocket).to have_received(:close_socket)
    end
  end

  describe 'private #handle_error' do
    let(:event) { double('WebSocket::Driver::ProtocolError', message: 'Connection failed') }

    it 'logs error message' do
      websocket.send(:handle_error, event)
      expect(logger).to have_received(:error).with('WebSocket error: Connection failed')
    end
  end
end
