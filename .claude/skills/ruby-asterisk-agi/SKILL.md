---
name: ruby-asterisk-agi
description: Build AGI/FastAGI dialplan logic in Ruby with ruby-asterisk: Server (Async+Fiber), Session command verbs, Protocol parsing, IVR patterns, 520 multi-line error handling.
---

# ruby-asterisk AGI / FastAGI

## When to use this skill

Use this skill when writing Ruby code that Asterisk calls via `AGI(agi://host:port)`. ruby-asterisk provides a FastAGI TCP server (`AGI::Server`) backed by the `async` gem's Fiber scheduler, plus a `Session` class with the full set of AGI command verbs.

## Core concepts

### Architecture

```
Asterisk          ruby-asterisk FastAGI server
   |                      |
   |--- TCP connect -----> AGI::Server (TCPServer + Async Sync)
   |                             |
   |                     spawns Fiber per connection
   |                             |
   |--- ENV block -------> Session#read_env  (parse agi_* vars)
   |--- CMD response <---- Session#<verb>    (write command, read result)
   |--- CMD response <---- ...
   |--- EOF / hangup ----> Fiber exits, socket closed
```

Each connection runs in its own **Fiber** sharing one OS thread. Socket reads/writes yield the Fiber rather than blocking, so thousands of simultaneous calls can be handled efficiently.

### Session execute model

Every command method writes a line to the socket and reads back a response:

```ruby
# Low-level (rarely called directly):
response = session.execute('ANSWER')
# => { code: 200, result: "0", data: nil }

# High-level convenience methods:
session.answer     # => { code: 200, result: "0", data: nil }
```

`execute` raises `RubyAsterisk::Error` on:
- EOF from Asterisk (`"Connection closed by Asterisk"`)
- Any 5xx response, after collecting the full `520-…/520 End of proper usage.` multi-line error body

### Protocol module

`RubyAsterisk::AGI::Protocol` is a stateless utility module (all class methods):

| Method | Purpose |
|---|---|
| `format_command(cmd, *args)` | Build a `"CMD arg1 arg2\n"` string with argument escaping |
| `escape_argument(arg)` | Pass through bare words; double-quote strings with spaces/special chars |
| `quote(arg)` | **Always** double-quote (use for filenames, variable values, messages) |
| `parse_response(line)` | Parse `"200 result=0 (data)"` → `{code:, result:, data:}` frozen Hash |
| `parse_env_line(line)` | Parse one `"agi_key: value"` line → `[key, value]` or `nil` |
| `parse_env_block(io, &block)` | Read env lines until blank, return `Hash{String=>String}` |
| `collect_multiline_error(first_line, first_resp, io)` | Drain 520 continuation lines |
| `error?(response)` | `response[:code] >= 500` |

**`quote` vs `escape_argument`**: use `quote` for filenames, variable values, and text that Asterisk requires always quoted; use `escape_argument` for digit-escape lists and simple identifiers that only need quoting when they contain spaces or special characters.

## FastAGI server

### Minimal setup

```ruby
require 'ruby-asterisk'

server = RubyAsterisk::AGI::Server.new('0.0.0.0', 4573)
server.handle do |session|
  session.answer
  session.stream_file('hello-world')
  session.hangup
end
server.run   # blocks until server.stop is called
```

In Asterisk `extensions.conf`:

```
exten => 100,1,AGI(agi://192.168.1.100:4573)
```

### Server API

| Method | Signature | Notes |
|---|---|---|
| `new` | `(host, port, logger: Logger.new($stdout))` | `port: 0` → ephemeral |
| `handle` | `(&block)` | Must be called before `run`; returns `self` |
| `run` | — | Blocks; raises `Error` if no handler |
| `stop` | — | Closes listener; active sessions finish naturally |
| `running?` | — | Boolean |
| `port` | — | Actual bound port (useful when `port: 0`) |

## Session command verbs

All methods return `{ code: Integer, result: String|nil, data: String|nil }`.

### Lifecycle and environment

```ruby
session.read_env     # parse initial agi_* block; fills session.env
session.env          # => { "agi_channel" => "SIP/alice-001", "agi_callerid" => "...", ... }
session.execute(cmd) # low-level: write cmd, read one response line
```

### Call control

```ruby
session.answer
session.hangup
session.hangup('SIP/alice-001')   # explicit channel
session.channel_status            # status of current channel (returns numeric code in result)
session.channel_status('SIP/b')   # explicit channel
```

### Audio playback

```ruby
session.stream_file('hello-world')           # play sound; no interrupt
session.stream_file('hello-world', '1234')   # play; stop on digit 1/2/3/4
session.stream_file('hello-world', '#*')     # stop on # or *

session.say_digits('12345')
session.say_digits('12345', '#')             # stop on #

session.say_number(42)
session.say_number(42, '#')
```

### DTMF / input collection

```ruby
result = session.get_data('enter-pin', timeout: 5000, max_digits: 4)
puts result[:data]   # => "1234" (digits entered) or "" on timeout

digit_ascii = session.wait_for_digit(5000)  # returns ASCII int, -1 on timeout
char = digit_ascii.chr if digit_ascii > 0
```

### Variables

```ruby
session.set_variable('MY_VAR', 'hello world')
response = session.get_variable('MY_VAR')
puts response[:data]   # => "hello world"
```

### Recording

```ruby
session.record_file(
  '/tmp/voicemail',      # filename (no extension)
  format: 'wav',         # default: 'wav'
  escape_digits: '#',    # stop on # (default)
  timeout_ms: 30_000,    # -1 = no timeout (default)
  offset: 0,
  beep: true,            # play beep before recording (default)
  silence: 3             # stop after 3 s of silence (optional)
)
```

### Dialplan application execution

```ruby
session.exec('Playback', 'hello-world')
session.exec('AGI', 'script.agi')
session.dial('PJSIP/bob', timeout: 30, options: 'r')   # wraps Exec Dial
```

### AstDB operations

```ruby
session.database_put('myapp', 'last_caller', '0391234567')
response = session.database_get('myapp', 'last_caller')
puts response[:data]                              # => "0391234567"
session.database_del('myapp', 'last_caller')
session.database_deltree('myapp')                 # delete whole family
session.database_deltree('myapp', 'sub/tree')     # delete sub-tree
```

### Utilities

```ruby
session.verbose('Starting IVR', level: 2)         # log to Asterisk CLI
session.send_text('Hello from FastAGI')
session.send_image('logo.png')
```

## Patterns

### Pattern 1: Minimal FastAGI (answer → play → hangup)

```ruby
server = RubyAsterisk::AGI::Server.new('0.0.0.0', 4573)
server.handle { |s| s.answer; s.stream_file('hello-world'); s.hangup }
server.run
```

### Pattern 2: IVR with DTMF branching

```ruby
server = RubyAsterisk::AGI::Server.new('0.0.0.0', 4573)
server.handle do |session|
  session.answer

  result = session.get_data('ivr-welcome', timeout: 5000, max_digits: 1)
  choice = result[:data].to_s.strip

  case choice
  when '1'
    session.dial('PJSIP/sales', timeout: 30)
  when '2'
    session.dial('PJSIP/support', timeout: 30)
  when '0'
    session.exec('VoiceMail', '1000@default')
  else
    session.stream_file('invalid-option')
    session.hangup
  end
end
server.run
```

### Pattern 3: Recording with error handling

```ruby
server = RubyAsterisk::AGI::Server.new('0.0.0.0', 4573)
server.handle do |session|
  session.answer
  session.stream_file('record-after-beep')

  begin
    session.record_file('/tmp/greeting',
                        format: 'wav',
                        escape_digits: '#',
                        timeout_ms: 30_000,
                        beep: true,
                        silence: 3)

    session.database_put('greetings', 'latest', '/tmp/greeting.wav')
    session.stream_file('your-recording-has-been-saved')
  rescue RubyAsterisk::Error => e
    # e.message contains the full 520 multi-line error body if applicable
    session.verbose("Recording failed: #{e.message}", level: 1)
    session.stream_file('an-error-occurred')
  ensure
    session.hangup
  end
end
server.run
```

### Pattern 4: All verbs — quick reference snippets

```ruby
# ---- Call control ----
session.answer                                    # ANSWER
session.hangup                                    # HANGUP
session.hangup('SIP/channel-001')                 # HANGUP <channel>
session.channel_status                            # CHANNEL STATUS
session.channel_status('SIP/channel-001')         # CHANNEL STATUS <channel>

# ---- Playback ----
session.stream_file('hello-world', '')            # STREAM FILE "hello-world" ""
session.say_digits('123', '#')                    # SAY DIGITS 123 "#"
session.say_number(42, '')                        # SAY NUMBER 42 ""

# ---- Input ----
session.get_data('enter-pin', timeout: 5000, max_digits: 4)  # GET DATA "enter-pin" 5000 4
session.wait_for_digit(5000)                      # WAIT FOR DIGIT 5000

# ---- Variables ----
session.set_variable('FOO', 'bar baz')            # SET VARIABLE FOO "bar baz"
session.get_variable('FOO')                       # GET VARIABLE FOO

# ---- Recording ----
session.record_file('/tmp/rec', format: 'wav', beep: true, silence: 3)

# ---- Execution ----
session.exec('Playback', 'hello-world')           # EXEC Playback "hello-world"
session.dial('PJSIP/alice', timeout: 30)          # EXEC Dial "PJSIP/alice,30"
session.verbose('log me', level: 1)               # VERBOSE "log me" 1

# ---- Text / image ----
session.send_text('Hello')                        # SEND TEXT "Hello"
session.send_image('logo.png')                    # SEND IMAGE logo.png

# ---- AstDB ----
session.database_put('family', 'key', 'value')    # DATABASE PUT family key "value"
session.database_get('family', 'key')             # DATABASE GET family key
session.database_del('family', 'key')             # DATABASE DEL family key
session.database_deltree('family')                # DATABASE DELTREE family
session.database_deltree('family', 'sub')         # DATABASE DELTREE family sub
```

## Gotchas

- **`handle` is mandatory** before `run`; calling `run` without it raises `RubyAsterisk::Error`.
- **`execute` raises on EOF** (`"Connection closed by Asterisk"`) and on any 5xx, including `520-…` multi-line errors. All command methods propagate this.
- **`Protocol.quote` vs `escape_argument`**: always use `quote` for filenames, variable values, and text content. Use `escape_argument` for digit-escape strings or other tokens that only need quoting conditionally.
- **Ruby 3.1**: an `IO#timeout` / `IO#timeout=` shim is applied at load time in `agi/server.rb`. Required because the `async` gem calls `io.timeout` inside its scheduler on Ruby 3.2+ — the shim returns `nil` on 3.1 to disable that path. Never remove it while Ruby 3.1 is in the support matrix.
- **CPU-bound work in handlers** will block the shared Fiber scheduler. Offload to a Thread or separate process if you need heavy computation per call.
- **`session.env` is populated by `read_env`** which is called automatically by `Server#serve`. In tests, call `session.read_env` manually after writing the env block to the socket.
- The `logger` on `Server` is passed down to each `Session`; unknown AGI env lines (not matching `agi_*:`) are logged at `debug` level.

## Source files

- `lib/ruby-asterisk/agi/server.rb` — `Server` class + `IO#timeout` shim
- `lib/ruby-asterisk/agi/session.rb` — `Session` class
- `lib/ruby-asterisk/agi/protocol.rb` — `Protocol` module
- `spec/ruby-asterisk/agi/server_spec.rb` — server lifecycle + Fiber concurrency proof
- `spec/ruby-asterisk/agi/session_spec.rb` — all command verbs, error handling
- `spec/ruby-asterisk/agi/protocol_spec.rb` — parsing and formatting helpers
