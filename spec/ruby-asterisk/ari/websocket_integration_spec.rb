# frozen_string_literal: true

require 'spec_helper'
require 'support/mock_ari_websocket_server'

RSpec.describe RubyAsterisk::ARI::WebSocket, 'integration' do
  let(:server) { MockAriWebSocketServer.new }
  let(:base_url) { "http://127.0.0.1:#{server.port}" }
  let(:logger) { Logger.new(File::NULL) }

  after do
    @websocket&.disconnect
    server.stop
  end

  def connect(options = {})
    opened = Queue.new
    defaults = { logger: logger, reconnect_delay: 0.1 }
    @websocket = described_class.new(base_url, 'api_key', 'test_app', defaults.merge(options))
    yield @websocket if block_given?
    @websocket.connect { opened << true }
    MockAriWebSocketServer.pop(opened)
    @websocket
  end

  it 'completes the handshake and fires the on_connect callback' do
    websocket = connect

    expect(websocket.connected?).to be(true)
  end

  it 'dispatches server events to registered callbacks' do
    received = Queue.new
    connect { |ws| ws.on('StasisStart') { |data| received << data } }

    server.broadcast('type' => 'StasisStart', 'channel' => { 'id' => '42' })

    event = MockAriWebSocketServer.pop(received)
    expect(event).to eq('type' => 'StasisStart', 'channel' => { 'id' => '42' })
  end

  it 'sends messages to the server' do
    websocket = connect

    expect(websocket.send_message?({ 'type' => 'ping' })).to be(true)
    expect(MockAriWebSocketServer.pop(server.messages)).to eq('{"type":"ping"}')
  end

  it 'sends pings at the configured interval' do
    connect(ping_interval: 0.1)

    expect(MockAriWebSocketServer.pop(server.pings)).not_to be_nil
  end

  it 'reconnects automatically after a connection drop' do
    received = Queue.new
    connect { |ws| ws.on('StasisStart') { |data| received << data } }
    MockAriWebSocketServer.pop(server.connections) # first handshake

    server.drop_clients
    MockAriWebSocketServer.pop(server.connections) # second handshake

    server.broadcast('type' => 'StasisStart')
    expect(MockAriWebSocketServer.pop(received)).to eq('type' => 'StasisStart')
  end

  it 'does not reconnect when auto_reconnect is disabled' do
    websocket = connect(auto_reconnect: false)
    thread = websocket.instance_variable_get(:@connection_thread)

    server.drop_clients

    expect(thread.join(2)).to eq(thread)
    expect(websocket.connected?).to be(false)
  end

  it 'stops cleanly on disconnect' do
    websocket = connect
    thread = websocket.instance_variable_get(:@connection_thread)

    websocket.disconnect

    expect(websocket.connected?).to be(false)
    expect(thread.alive?).to be(false)
  end
end
