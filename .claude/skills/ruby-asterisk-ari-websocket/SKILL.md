---
name: ruby-asterisk-ari-websocket
description: Receive real-time ARI events from Asterisk via WebSocket with ruby-asterisk: StasisStart, ChannelStateChange, auto-reconnect, ping keep-alive, per-event callbacks.
---

# ruby-asterisk ARI WebSocket Client

## When to use this skill

Use this skill when you need to react to Asterisk events in real time — for example: starting call handling logic when a Stasis call arrives (`StasisStart`), updating a dashboard on channel state changes, or forwarding events to another system.

## Core concepts

- The WebSocket client runs an **EventMachine reactor in a background thread**. `connect` returns immediately; event processing happens in that thread.
- Register handlers with `on(event_type, &block)` before or after connecting — handlers are stored and called whenever a matching event arrives.
- **Multiple handlers** for the same event type are supported; all are called in registration order.
- Auto-reconnect is enabled by default. When the connection drops, the client waits `reconnect_delay` seconds and reconnects. Set `auto_reconnect: false` to disable.
- A ping is sent every `ping_interval` seconds to keep the connection alive.

## Initialize

```ruby
require 'ruby-asterisk'

ws = RubyAsterisk::ARI::WebSocket.new(
  'http://192.168.1.1:8088',    # ARI base URL
  'my_api_key',                 # API key (HTTP Basic auth username)
  'my_stasis_app',              # Stasis application name
  auto_reconnect:  true,        # default: true
  reconnect_delay: 5,           # seconds between reconnect attempts; default: 5
  ping_interval:   30,          # keep-alive ping interval in seconds; default: 30
  logger:          Logger.new($stdout)
)
```

## API reference

| Method | Signature | Notes |
|---|---|---|
| `on` | `(event_type, &block)` | Register a callback; `event_type` is a String or Symbol |
| `connect` | `(&block)` | Start the connection; optional block called on connect |
| `connected?` | — | `true` if socket is open and in OPEN state |
| `send_message?` | `(message)` | Send Hash (auto-JSON) or String; returns `false` if not connected |
| `disconnect` | — | Close the socket and disable auto-reconnect |

Constants (readable as class constants):

| Constant | Default |
|---|---|
| `PING_INTERVAL` | 30 s |
| `RECONNECT_DELAY` | 5 s |
| `MAX_RECONNECT_ATTEMPTS` | `nil` (infinite) |

## Common ARI event types

| Event type | When fired |
|---|---|
| `StasisStart` | A channel enters your Stasis application |
| `StasisEnd` | A channel leaves your Stasis application |
| `ChannelStateChange` | Channel state changes (ringing, up, etc.) |
| `ChannelDtmfReceived` | DTMF digit received on a channel |
| `ChannelHangupRequest` | Hangup requested on a channel |
| `BridgeCreated` / `BridgeDestroyed` | Bridge lifecycle |
| `ChannelEnteredBridge` / `ChannelLeftBridge` | Channel bridge membership |
| `PlaybackStarted` / `PlaybackFinished` | Media playback lifecycle |

Event payloads are plain Ruby Hashes (parsed from JSON). The outer `type` key matches the event type string.

## Usage patterns

### React to incoming Stasis calls

```ruby
ws.on('StasisStart') do |event|
  channel_id = event['channel']['id']
  caller_id  = event.dig('channel', 'caller', 'number')
  puts "Incoming call from #{caller_id} on #{channel_id}"

  # Use ARI HTTP client to control the channel
  http = RubyAsterisk::ARI::Client.new('http://192.168.1.1:8088', 'key', 'my_stasis_app')
  http.channels.get(channel_id).answer
end

ws.connect
sleep   # keep main thread alive
```

### Handle disconnect and cleanup

```ruby
ws.on('StasisEnd') do |event|
  puts "Call ended: #{event['channel']['id']}"
end

ws.connect do
  puts "Connected to ARI WebSocket"
end

# Graceful shutdown
at_exit { ws.disconnect }
```

### Conditional forwarding

```ruby
ws.on('ChannelStateChange') do |event|
  next unless event.dig('channel', 'state') == 'Up'

  channel_id = event['channel']['id']
  puts "Channel #{channel_id} is now answered"
end
```

### Combine with ARI HTTP client

```ruby
http = RubyAsterisk::ARI::Client.new('http://192.168.1.1:8088', 'key', 'app')

ws = RubyAsterisk::ARI::WebSocket.new('http://192.168.1.1:8088', 'key', 'app')
ws.on('StasisStart') do |event|
  channel = http.channels.get(event['channel']['id'])
  channel.answer
  channel.play('sound:hello-world')
end

ws.connect
sleep
```

## Gotchas

- **`connect` is non-blocking** — it starts a background EventMachine thread and returns `self`. The main thread must stay alive (e.g. `sleep`) for the event loop to run.
- **Callbacks execute in the EventMachine thread** — avoid long-running or blocking operations in callbacks; offload to a separate thread if needed.
- **`send_message?` returns `false`** when not connected — always check the return value if delivery matters.
- **Auto-reconnect** is enabled by default. Call `disconnect` when you actually want to stop; just closing the socket will trigger a reconnect.
- **`app_name` must match** the Stasis application in Asterisk; events from other applications are not forwarded.
- Calling `on` after `connect` is safe — handlers are stored in a plain Hash and checked on each incoming message.

## Source files

- `lib/ruby-asterisk/ari/websocket.rb` — `WebSocket` class
- `lib/ruby-asterisk/ari/websocket/connection.rb` — `Connection` module (establish, ping, reconnect)
- `lib/ruby-asterisk/ari/websocket/event_handlers.rb` — `EventHandlers` module (dispatch callbacks)
- `spec/ruby-asterisk/ari/websocket_spec.rb`
