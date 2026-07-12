# ruby-asterisk

[![Maintainability](https://api.codeclimate.com/v1/badges/2861728929db934eb376/maintainability)](https://codeclimate.com/github/emilianodellacasa/ruby-asterisk/maintainability)

A Ruby client for [Asterisk PBX](https://www.asterisk.org/) covering three interfaces:

| Interface | Use case | Entry point | Concurrency model |
|---|---|---|---|
| **AMI** | TCP command/event channel | `RubyAsterisk::AMI::Client` | Threads + Promise (non-blocking) |
| **ARI HTTP** | REST control API | `RubyAsterisk::ARI::Client` | Synchronous (Faraday) |
| **ARI WebSocket** | Real-time event stream | `RubyAsterisk::ARI::WebSocket` | websocket-driver + Threads |
| **AGI / FastAGI** | In-process dialplan logic | `RubyAsterisk::AGI::Server` | Async + Fibers |

## Requirements

- **Ruby ≥ 3.1**
- Runtime dependencies: `async ~> 2.0`, `faraday >= 1.0`, `websocket-driver ~> 0.8`

> **Ruby 3.1 note**: the `IO#timeout` shim required by the Async Fiber scheduler is applied automatically when the AGI module is loaded — no action needed.

## Installation

```ruby
gem 'ruby-asterisk'
```

```bash
bundle install
```

## AMI — Asterisk Manager Interface

### Initialize and connect

```ruby
require 'ruby-asterisk'

ami = RubyAsterisk::AMI::Client.new(host: '192.168.1.1', port: 5038)
ami.connect
```

### The Promise model

Every AMI command returns a `RubyAsterisk::AMI::Promise` immediately — it does **not** block. Call `.value(timeout)` to wait for the `Response`:

```ruby
promise  = ami.ping          # returns immediately
response = promise.value     # blocks up to 5 s (default)
response = promise.value(10) # custom timeout in seconds

puts response.success        # => true
puts response.message        # => "Pong"
puts response.action_id      # => "lk3m0p..."
puts response.data           # => structured Hash or Array depending on command
puts response.raw_response   # => raw AMI text

# On timeout:
begin
  response = promise.value(2)
rescue Timeout::Error => e
  puts e.message
end
```

`disconnect` rejects all pending promises with a `RuntimeError`.

### Login / Logoff

```ruby
ami.login(username: 'mark', secret: 'mysecret').value
ami.logoff.value
```

### System commands

```ruby
ami.ping.value
ami.command('core show channels').value
ami.wait_event(timeout: -1).value     # -1 = wait forever
ami.event_mask('on').value            # enable event delivery on this connection
ami.parked_calls.value
ami.device_state_list.value
ami.skinny_devices.value
ami.skinny_lines.value
```

### Channel commands

```ruby
ami.core_show_channels.value
ami.status.value                      # all channels
ami.status(channel: 'SIP/alice-001').value

# Originate: channel, context, callee, priority
ami.originate('SIP/9100', 'OUTGOING', '123456', '1',
              caller_id: 'Alice',
              variable: 'var1=12,var2=99',
              timeout: 30_000,
              async: true).value

# Originate to application
ami.originate_app(channel: 'SIP/9100',
                  application: 'Playback',
                  data: 'hello-world',
                  async: true).value

ami.redirect('SIP/alice-001', 'default', '100', '1').value
ami.hangup('SIP/alice-001').value
ami.atxfer(channel: 'SIP/alice-001',
           exten: '200',
           context: 'default',
           priority: '1').value
```

### Queue commands

```ruby
ami.queues.value
ami.queue_status.value
ami.queue_summary('support').value
ami.queue_add('support', 'SIP/agent1', penalty: 1, member_name: 'Alice').value
ami.queue_remove(queue: 'support', interface: 'SIP/agent1').value
ami.queue_pause(interface: 'SIP/agent1',
                paused: true,
                queue: 'support',
                reason: 'lunch').value
```

### Conference commands

```ruby
ami.meet_me_list.value
ami.confbridges.value                          # list all ConfBridge rooms
ami.confbridge('my-room').value                # list participants in a room
ami.confbridge_mute(conference: 'my-room',   channel: 'SIP/alice-001').value
ami.confbridge_unmute(conference: 'my-room', channel: 'SIP/alice-001').value
ami.confbridge_kick(conference: 'my-room',   channel: 'SIP/alice-001').value
```

### Mailbox commands

```ruby
ami.mailbox_status(mailbox: '1001', context: 'default').value
ami.mailbox_count(mailbox: '1001', context: 'default').value
```

### SIP commands

```ruby
ami.sip_peers.value
ami.sip_show_peer('alice').value
ami.sip_show_registry.value
```

### Extension state

```ruby
response = ami.extension_state(exten: '1001', context: 'default').value
puts response.data[:hints]
# => [{ "Exten" => "1001", "Status" => "1",
#        "DescriptiveStatus" => "In Use", ... }]
```

Status values from `RubyAsterisk::DESCRIPTIVE_STATUS`:
`-1` Not found · `0` Idle · `1` In Use · `2` Busy · `4` Unavailable · `8` Ringing · `16` On Hold

### Monitor commands

```ruby
ami.monitor('SIP/alice-001', mix: true, file: '/tmp/call', format: 'wav').value
ami.pause_monitor('SIP/alice-001').value
ami.unpause_monitor('SIP/alice-001').value
ami.change_monitor(channel: 'SIP/alice-001', file: '/tmp/call2').value
ami.stop_monitor('SIP/alice-001').value
```

### Disconnect

```ruby
ami.disconnect
```

### The Response object

| Attribute | Type | Description |
|---|---|---|
| `success` | Boolean | `true` when raw response contains `Response: Success` |
| `action_id` | String | ActionID echoed by Asterisk |
| `message` | String | `Message:` field from the response |
| `data` | Hash / Array | Structured data parsed by `ResponseParser` (see `PARSE_DATA`) |
| `raw_response` | String/Array | The unprocessed AMI text |
| `type` | String | The AMI action name |

Commands with structured `data` parsing (`PARSE_DATA`): `CoreShowChannels`, `ParkedCalls`, `Originate`, `MeetMeList`, `ConfbridgeListRooms`, `ConfbridgeList`, `Status`, `ExtensionState`, `DeviceStateList`, `SKINNYdevices`, `SKINNYlines`, `QueuePause`, `Pong`, `Events`, `SIPpeers`, `SIPshowpeer`.

---

## ARI — Asterisk REST Interface

### Initialize

```ruby
require 'ruby-asterisk'

client = RubyAsterisk::ARI::Client.new(
  'http://192.168.1.1:8088',  # ARI base URL
  'my_api_key',               # API key (username; password is empty)
  'my_stasis_app'             # Stasis application name
)
```

### Asterisk info

```ruby
info = client.asterisk_info
puts info['system']['version']
```

### Channels

```ruby
channel = client.channels.get('1553112062.1')
puts channel.id             # => "1553112062.1"
puts channel.data['name']   # => "PJSIP/alice-00000001"

channels = client.channels.list
channels.each { |ch| puts ch.data['name'] }

channel.ring
channel.answer
channel.play('sound:hello-world')
channel.play('sound:tt-monkeys', playbackId: 'pb-1')
channel.hangup
```

### Bridges

```ruby
bridges = client.bridges.list
bridge  = client.bridges.get('my-bridge-id')

bridge.add_channel('1553112062.1')
bridge.remove_channel('1553112062.1')
bridge.destroy
```

### Playbacks

```ruby
playback = client.playbacks.get('pb-1')
playback.control('pause')
playback.control('unpause')
playback.control('restart')
playback.stop
```

### Endpoints

```ruby
endpoints = client.endpoints.list
endpoints.each do |ep|
  puts "#{ep.technology}/#{ep.resource} — #{ep.state}"
end
```

### Error handling

All ARI methods raise `RubyAsterisk::Error` on HTTP 4xx/5xx:

```ruby
begin
  channel = client.channels.get('nonexistent-id')
rescue RubyAsterisk::Error => e
  puts e.message  # => "Channel not found"
end
```

---

## ARI WebSocket — Real-time events

### Initialize and connect

```ruby
require 'ruby-asterisk'

ws = RubyAsterisk::ARI::WebSocket.new(
  'http://192.168.1.1:8088',
  'my_api_key',
  'my_stasis_app',
  auto_reconnect: true,    # default: true
  reconnect_delay: 5,      # seconds between attempts, default: 5
  ping_interval: 30,       # keep-alive ping interval, default: 30
  logger: Logger.new($stdout)
)
```

### Register event handlers

```ruby
ws.on('StasisStart') do |event|
  puts "Call arrived on channel #{event['channel']['id']}"
end

ws.on('ChannelStateChange') do |event|
  puts "Channel state: #{event['channel']['state']}"
end

ws.on('StasisEnd') do |event|
  puts "Call ended: #{event['channel']['id']}"
end
```

Multiple handlers for the same event type are supported.

### Connect and disconnect

```ruby
ws.connect do |sock|
  puts "WebSocket connected"
end

# Check status
ws.connected?   # => true / false

# Send a message (returns false if not connected)
ws.send_message?({ type: 'ping' })

# Disconnect (disables auto-reconnect)
ws.disconnect
```

> **Threading note**: `connect` starts a background connection thread that owns the socket read loop. Event callbacks execute in that thread — avoid direct UI updates or non-thread-safe operations inside callbacks.

---

## AGI — FastAGI server

### What is FastAGI?

FastAGI lets you run the AGI dialplan logic in an external process that Asterisk connects to via TCP. ruby-asterisk provides a server that handles each Asterisk connection in its own Fiber under the `async` gem, so many concurrent calls share a single OS thread.

In Asterisk's `extensions.conf`:

```
exten => 100,1,AGI(agi://192.168.1.100:4573)
```

### Initialize and start

```ruby
require 'ruby-asterisk'

server = RubyAsterisk::AGI::Server.new('0.0.0.0', 4573, logger: Logger.new($stdout))
server.handle do |session|
  session.answer
  session.stream_file('hello-world')
  session.hangup
end
server.run   # blocks until server.stop is called
```

The handler block **must** be registered with `handle` before calling `run`, otherwise `RubyAsterisk::Error` is raised.

### Ephemeral port

Pass `port: 0` to bind to any free port; the actual bound port is available in `server.port` after `run` starts.

### Stop

```ruby
# In a signal handler or another thread:
server.stop
```

Active sessions finish naturally after `stop` is called.

### The Session object

Inside the handler block, `session` is a `RubyAsterisk::AGI::Session`. All command methods return a Hash: `{ code: Integer, result: String|nil, data: String|nil }`.

**Environment**

```ruby
session.env
# => { "agi_network" => "yes", "agi_channel" => "SIP/alice-001",
#      "agi_callerid" => "0391234567", ... }
```

**Call control**

```ruby
session.answer
session.hangup
session.hangup('SIP/alice-001')   # explicit channel
session.channel_status            # status of current channel
session.channel_status('SIP/b')   # explicit channel
```

**Audio playback**

```ruby
session.stream_file('hello-world')          # play; no escape digits
session.stream_file('hello-world', '1234')  # play; stop on digit 1/2/3/4
session.say_digits('12345')
session.say_digits('12345', '#')            # stop on #
session.say_number(42)
session.say_number(42, '#*')
```

**DTMF and input**

```ruby
result = session.get_data('enter-pin', timeout: 5000, max_digits: 4)
# Like every verb, returns the response Hash; the key's ASCII value
# (or -1 on timeout) is in response[:result].
response = session.wait_for_digit(5000)
digit    = response[:result]
```

**Variables**

```ruby
session.set_variable('MY_VAR', 'hello')
response = session.get_variable('MY_VAR')
puts response[:data]   # => "hello"
```

**Recording**

```ruby
session.record_file('/tmp/greeting',
                    format: 'wav',
                    escape_digits: '#',
                    timeout_ms: 10_000,
                    beep: true,
                    silence: 3)
```

**Execute dialplan application**

```ruby
session.exec('Playback', 'hello-world')
session.dial('PJSIP/bob', timeout: 30, options: 'r')
```

**AstDB**

```ruby
session.database_put('myapp', 'last_caller', '0391234567')
response = session.database_get('myapp', 'last_caller')
puts response[:data]   # => "0391234567"
session.database_del('myapp', 'last_caller')
session.database_deltree('myapp')
```

**Logging and text**

```ruby
session.verbose('Starting IVR flow', level: 2)
session.send_text('Hello from AGI')
session.send_image('logo.png')
```

### IVR example — DTMF menu

```ruby
server = RubyAsterisk::AGI::Server.new('0.0.0.0', 4573)
server.handle do |session|
  session.answer

  result  = session.get_data('ivr-menu', timeout: 5000, max_digits: 1)
  choice  = result[:data].to_s.strip

  case choice
  when '1'
    session.dial('PJSIP/sales', timeout: 30)
  when '2'
    session.dial('PJSIP/support', timeout: 30)
  else
    session.stream_file('invalid-option')
  end

  session.hangup
end
server.run
```

### Recording example — with error handling

```ruby
server = RubyAsterisk::AGI::Server.new('0.0.0.0', 4573)
server.handle do |session|
  session.answer
  session.stream_file('beep')

  begin
    session.record_file('/tmp/message', format: 'wav',
                        escape_digits: '#', timeout_ms: 30_000,
                        beep: false, silence: 5)
    session.database_put('voicemail', 'last_recording', '/tmp/message')
  rescue RubyAsterisk::Error => e
    # e.message includes the 520 multi-line error body
    session.verbose("Recording failed: #{e.message}", level: 1)
  end

  session.hangup
end
server.run
```

### Error handling in sessions

`session.execute` (the underlying method) raises `RubyAsterisk::Error`:
- On EOF: `"Connection closed by Asterisk"`
- On AGI 5xx responses, including multi-line `520-…/520 End of proper usage.` errors

All command methods (`answer`, `stream_file`, etc.) are thin wrappers around `execute` and propagate the same exception.

---

## LLM skill files

Detailed how-to guides for each subsystem are in `.claude/skills/`. Claude Code loads them automatically as project-level skills; other agent runners can read them as markdown prompts.

| Skill file | Covers |
|---|---|
| `.claude/skills/ruby-asterisk-ami/SKILL.md` | AMI async client, Promise model, all command groups |
| `.claude/skills/ruby-asterisk-ari/SKILL.md` | ARI HTTP client, resources, error handling |
| `.claude/skills/ruby-asterisk-ari-websocket/SKILL.md` | ARI WebSocket events, callbacks, reconnect |
| `.claude/skills/ruby-asterisk-agi/SKILL.md` | FastAGI server, Session verbs, IVR and recording patterns |

---

## Development

```bash
bundle install
bundle exec rake spec     # run all tests
bundle exec rubocop       # code quality checks
```

Test infrastructure: `spec/support/mock_ami_server.rb` provides a mock AMI server for unit tests.

Questions or issues? Please use the [issue tracker](https://github.com/emilianodellacasa/ruby-asterisk/issues). Contributions via fork + pull request are welcome.

This gem was created by Emiliano Della Casa and is licensed under the MIT License, distributed by courtesy of [Engim srl](http://www.engim.eu/en).
