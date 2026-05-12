---
name: ruby-asterisk-ari
description: Use the Asterisk REST Interface with ruby-asterisk: channels, bridges, playbacks, endpoints via HTTP, and RubyAsterisk::Error for 4xx/5xx handling.
---

# ruby-asterisk ARI HTTP Client

## When to use this skill

Use this skill when writing code that controls Asterisk channels or bridges via the ARI REST API — for example: answering calls from a Stasis application, mixing channels into a bridge, controlling media playback, or inspecting endpoint registration state.

## Core concepts

- The client is **synchronous** (backed by Faraday). Every method blocks and returns the parsed JSON body (Hash or Array) or raises `RubyAsterisk::Error`.
- Resources are accessed via `Collection` objects (`client.channels`, `client.bridges`, etc.); each collection supports `list` and `get(id)`.
- Individual resource objects have a `data` Hash with the full JSON representation, plus convenience methods for actions.
- **`app_name`** must match the Stasis application declared in Asterisk's `ari.conf`; mismatches cause channels to be rejected or events to be silently dropped.

## Initialize

```ruby
require 'ruby-asterisk'

client = RubyAsterisk::ARI::Client.new(
  'http://192.168.1.1:8088',   # ARI base URL (no trailing slash)
  'my_api_key',                # API key used as HTTP Basic auth username
  'my_stasis_app'              # Stasis application name
)
```

## API reference

### Asterisk info

```ruby
info = client.asterisk_info
# => Hash with keys "build", "system", "config", "status"
puts info['system']['version']
```

### Channels — `client.channels`

| Method | Signature | Returns |
|---|---|---|
| `list` | — | Array of `Channel` |
| `get` | `(id)` | `Channel` |

**Channel actions:**

| Method | Notes |
|---|---|
| `channel.id` | Channel identifier string |
| `channel.data` | Full JSON Hash from ARI |
| `channel.ring` | Send ringing indication |
| `channel.answer` | Answer the channel |
| `channel.play(media, **opts)` | Play audio; `media` = `'sound:hello-world'` |
| `channel.hangup` | Hang up and destroy |

### Bridges — `client.bridges`

| Method | Signature | Returns |
|---|---|---|
| `list` | — | Array of `Bridge` |
| `get` | `(id)` | `Bridge` |

**Bridge actions:**

| Method | Notes |
|---|---|
| `bridge.id` | Bridge identifier |
| `bridge.data` | Full JSON Hash |
| `bridge.add_channel(channel_id)` | Mix a channel into the bridge |
| `bridge.remove_channel(channel_id)` | Remove a channel |
| `bridge.destroy` | Destroy the bridge |

### Playbacks — `client.playbacks`

| Method | Signature | Returns |
|---|---|---|
| `get` | `(id)` | `Playback` |

**Playback actions:**

| Method | Notes |
|---|---|
| `playback.control('pause')` | Pause playback |
| `playback.control('unpause')` | Resume |
| `playback.control('restart')` | Restart from beginning |
| `playback.stop` | Stop and destroy |

### Endpoints — `client.endpoints`

| Method | Signature | Returns |
|---|---|---|
| `list` | — | Array of `Endpoint` |

**Endpoint attributes:**

| Method | Notes |
|---|---|
| `ep.technology` | e.g. `'PJSIP'`, `'SIP'` |
| `ep.resource` | e.g. `'alice'` |
| `ep.state` | `'online'` / `'offline'` |
| `ep.data` | Full JSON Hash |

## Error handling

All methods raise `RubyAsterisk::Error` for HTTP 4xx/5xx responses:

```ruby
begin
  channel = client.channels.get('nonexistent')
rescue RubyAsterisk::Error => e
  puts e.message  # => "Channel not found"
end
```

The error message comes from the JSON `message` field if present, otherwise from the HTTP reason phrase.

## Usage patterns

### Answer a Stasis channel and bridge two callers

```ruby
channel_a = client.channels.get(event_channel_a_id)
channel_b = client.channels.get(event_channel_b_id)

bridge = client.bridges.list.first || begin
  # bridges.list returns all existing bridges; create via ARI REST directly if none
end

channel_a.answer
channel_b.answer

bridge.add_channel(channel_a.id)
bridge.add_channel(channel_b.id)
```

### Play audio and track playback

```ruby
channel.play('sound:tt-monkeys', playbackId: 'pb-greeting')
pb = client.playbacks.get('pb-greeting')
pb.control('pause')
sleep 2
pb.control('unpause')
pb.stop
```

### List all online PJSIP endpoints

```ruby
online = client.endpoints.list.select { |ep| ep.technology == 'PJSIP' && ep.state == 'online' }
online.each { |ep| puts ep.resource }
```

## Gotchas

- **Basic auth**: `api_key` is the **username**; the password is always empty (`''`). Check `ari.conf` if you get 401 errors.
- **`app_name` must match** the Stasis application configured in Asterisk; channels not subscribed to your app will not deliver events to the WebSocket client.
- **JSON parse fallback**: if the response body is not valid JSON, the raw string is returned instead of a Hash. This can happen with some error responses.
- **`client.channels.list`** returns an empty array (not nil) when no channels are active.

## Source files

- `lib/ruby-asterisk/ari/client.rb` — `Client` class
- `lib/ruby-asterisk/ari/resources/channel.rb` — `Channel` resource
- `lib/ruby-asterisk/ari/resources/bridge.rb` — `Bridge` resource
- `lib/ruby-asterisk/ari/resources/playback.rb` — `Playback` resource
- `lib/ruby-asterisk/ari/resources/endpoint.rb` — `Endpoint` resource
- `lib/ruby-asterisk/ari/resources/collection.rb` — `Collection` (list/get)
- `lib/ruby-asterisk/ari/resources/base.rb` — `Base` resource (id, data)
- `spec/ruby-asterisk/ari/client_spec.rb`
- `spec/ruby-asterisk/ari/resources/`
