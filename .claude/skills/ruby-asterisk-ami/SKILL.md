---
name: ruby-asterisk-ami
description: Build an async Asterisk AMI client with ruby-asterisk: connect, login, Promise-based commands (channel, queue, conference, SIP, mailbox, monitor, extension state).
---

# ruby-asterisk AMI Client

## When to use this skill

Use this skill when writing code that connects to the Asterisk Manager Interface via TCP — for example: originating calls, checking extension state, managing queues, monitoring channels, or handling SIP peers.

## Core concepts

### Every command returns a Promise

```ruby
promise  = ami.ping          # returns RubyAsterisk::AMI::Promise immediately
response = promise.value     # blocks up to 5 s (default timeout)
response = promise.value(10) # custom timeout in seconds
```

`#value` raises `Timeout::Error` if no response arrives within the timeout.
`disconnect` rejects all pending promises with `RuntimeError`.

### The Response object

| Attribute | Type | Notes |
|---|---|---|
| `success` | Boolean | `true` when raw contains `Response: Success` |
| `action_id` | String | echoed ActionID |
| `message` | String | `Message:` field |
| `data` | Hash / Array | structured, present when action is in `PARSE_DATA` |
| `raw_response` | String/Array | unprocessed AMI text |
| `type` | String | AMI action name |

### Connection lifecycle

```ruby
ami = RubyAsterisk::AMI::Client.new(host: '192.168.1.1', port: 5038)
ami.connect                                        # starts the reader + writer threads
ami.login(username: 'admin', secret: 'secret').value
# ... use commands ...
ami.logoff.value
ami.disconnect                                     # stops both threads, rejects pending promises
```

`login` auto-calls `connect` if not already connected.

## API reference

### System

| Method | AMI Action | Notes |
|---|---|---|
| `ping` | `Ping` | Returns `Pong` response |
| `command(cmd)` | `Command` | CLI passthrough, e.g. `'core show channels'` |
| `wait_event(timeout: -1)` | `WaitEvent` | negative = wait forever, so `#value` has no deadline; a positive value bounds it (floor: the client default) |
| `event_mask(mask = 'off')` | `Events` | `'on'` / `'off'` / `'system,call'` |
| `parked_calls` | `ParkedCalls` | |
| `device_state_list` | `DeviceStateList` | |
| `skinny_devices` | `SKINNYdevices` | |
| `skinny_lines` | `SKINNYlines` | |

### Channel

| Method | Signature | AMI Action |
|---|---|---|
| `core_show_channels` | — | `CoreShowChannels` |
| `status` | `(channel: nil, action_id: nil)` | `Status` |
| `originate` | `(channel, context, callee, priority, variable: nil, caller_id: nil, timeout: 30_000, async: nil)` | `Originate` |
| `originate_app` | `(channel:, application:, data:, async:)` | `Originate` (Application/Data form) |
| `redirect` | `(channel, context, callee, priority, variable: nil, caller_id: nil, timeout: 30_000)` | `Redirect` |
| `hangup` | `(channel)` | `Hangup` |
| `atxfer` | `(channel:, exten:, context:, priority: '1')` | `Atxfer` |

### Queue

| Method | Signature |
|---|---|
| `queues` | — |
| `queue_status` | — |
| `queue_summary` | `(queue)` |
| `queue_add` | `(queue, interface, penalty: 2, paused: false, member_name: '')` |
| `queue_remove` | `(queue:, interface:)` |
| `queue_pause` | `(interface:, paused:, queue:, reason: 'none')` |

### Conference

| Method | Signature |
|---|---|
| `meet_me_list` | — |
| `confbridges` | — |
| `confbridge` | `(conference)` |
| `confbridge_mute` | `(conference:, channel:)` |
| `confbridge_unmute` | `(conference:, channel:)` |
| `confbridge_kick` | `(conference:, channel:)` |

### Mailbox

| Method | Signature |
|---|---|
| `mailbox_status` | `(mailbox:, context: 'default')` |
| `mailbox_count` | `(mailbox:, context: 'default')` |

### SIP

| Method | Signature |
|---|---|
| `sip_peers` | — |
| `sip_show_peer` | `(peer)` |
| `sip_show_registry` | — |

### Extension

| Method | Signature | Notes |
|---|---|---|
| `extension_state` | `(exten:, context:, action_id: nil)` | `data[:hints]` decorated with `DescriptiveStatus` |

### Monitor

| Method | Signature |
|---|---|
| `monitor` | `(channel, mix: false, file: nil, format: 'wav')` |
| `stop_monitor` | `(channel)` |
| `pause_monitor` | `(channel)` |
| `unpause_monitor` | `(channel)` |
| `change_monitor` | `(channel:, file:)` |

## Usage patterns

### Minimal connect + command

```ruby
ami = RubyAsterisk::AMI::Client.new(host: '127.0.0.1', port: 5038)
ami.login(username: 'admin', secret: 'secret').value
response = ami.ping.value
puts response.success   # => true
ami.disconnect
```

### Originate and wait for result

```ruby
promise  = ami.originate('PJSIP/alice', 'outbound', '0391234567', '1', async: true)
response = promise.value(30)
puts response.success
```

### Poll queue status

```ruby
loop do
  members = ami.queue_status.value.data
  members&.each { |m| puts m.inspect }
  sleep 5
end
```

### Handle Timeout::Error

```ruby
begin
  response = ami.originate('SIP/slow', 'default', '100', '1').value(2)
rescue Timeout::Error
  puts 'AMI did not respond in time'
end
```

## Gotchas

- **ActionID is auto-generated** (monotonic nanosecond clock in base36 plus an atomic counter). A caller-supplied `action_id:` replaces it — including in the `Promise` used for correlation — so it must be unique among in-flight commands.
- **Call `event_mask('on')`** on the connection if you need Asterisk to push async events (e.g. `StasisStart`). Off by default. Note that `AMI::Client` currently discards received events: there is no public subscription API yet.
- **`timeout:` is per command** and never mutates the client-wide default; `wait_event(timeout: -1)` builds a promise with no deadline, so bound it with `value(seconds)` if you must not block forever.
- **`disconnect` rejects all pending promises** — check for `RuntimeError` if you disconnect mid-flight.
- **`PARSE_DATA`** (`lib/ruby-asterisk/parsing_constants.rb`) controls which responses get structured `data`; unlisted actions return the raw string.
- The version constant is now `RubyAsterisk::VERSION` (was `Rami::VERSION` before 1.0.0).

## Source files

- `lib/ruby-asterisk/ami/client.rb` — `Client` class
- `lib/ruby-asterisk/ami/reactor.rb` — reader/writer threads owning the socket
- `lib/ruby-asterisk/ami/parser.rb` — stateless AMI frame parser
- `lib/ruby-asterisk/ami/promise.rb` — `Promise` class
- `lib/ruby-asterisk/ami/commands/*.rb` — command modules
- `lib/ruby-asterisk/response.rb` — `Response` class
- `lib/ruby-asterisk/parsing_constants.rb` — `PARSE_DATA`, `DESCRIPTIVE_STATUS`
- `spec/ruby-asterisk/ami/async_client_spec.rb` — integration tests
