# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-07-25

First release of the rewritten gem: three interfaces (AMI, ARI, AGI) on Ruby ≥ 3.1.

### Added

- **AGI::Protocol** — stateless module for AGI wire protocol: `format_command`, `escape_argument`, `quote`, `parse_response`, `error?` (#55)
- **AGI::Protocol env helpers** — `parse_env_line`, `parse_env_block`, `collect_multiline_error` for robust Asterisk environment parsing and 520 multi-line error handling (#56)
- **AGI::Session** — full FastAGI session wrapper with fiber-friendly socket I/O: `answer`, `hangup`, `stream_file`, `say_digits`, `say_number`, `exec`, `set_variable`, `get_variable`, `get_data`, `verbose`, `dial`, `wait_for_digit`, `record_file`, `send_text`, `send_image`, `channel_status`, `database_get/put/del/deltree` (#55)
- **AGI::Server** — FastAGI TCP server backed by Async + Fiber scheduler; each connection runs in its own Fiber sharing a single OS thread (#54)
- **ARI::WebSocket** — WebSocket client for ARI real-time events: per-event callbacks via `on(type, &block)`, auto-reconnect, configurable ping keep-alive. Built on the pure Ruby `websocket-driver` gem over a plain `TCPSocket` (`SSLSocket` for https) — no EventMachine, so it installs and runs on every supported Ruby including 4.x: a connection thread owns connect/read-loop/reconnect, a ping thread sends keep-alives, and driver access is serialized through a reentrant Monitor so `send_message?` is thread-safe (#53, #82)
- **ARI::Client** — HTTP client for the Asterisk REST Interface backed by Faraday (#51)
- **ARI::Resources** — Channel, Bridge, Playback, Endpoint, Collection, and Base resource classes for the ARI HTTP client (#52)
- **AMI::Client async rewrite** — non-blocking AMI client with `Promise`-based responses: every command returns a `Promise`, call `.value(timeout)` to materialise the `Response`. The connection lives in a `Reactor` made of two plain OS threads (reader + writer) around the stateless `Parser` module, which gives deterministic shutdown on all Ruby ≥ 3.1 (#48, #49, #50, #79)
- **AMI command modules** — Channel, Conference, Extension, Mailbox, Monitor, Queue, Sip, System extracted into dedicated modules and mixed into `AMI::Client` (#47)
- `logoff` method on `AMI::Client`

### Changed

- **BREAKING:** `RubyAsterisk::AMI::Client` replaces the legacy flat `RubyAsterisk::AMI` class; every command now returns `RubyAsterisk::AMI::Promise` instead of a synchronous `Response`.
- **BREAKING:** `Rami::VERSION` renamed to `RubyAsterisk::VERSION`; callers reading `Rami::VERSION` will get a `NameError`.
- Minimum Ruby version set to 3.1.
- Immutable domain objects (`Request`, `Response`) are now deep-frozen (#45).
- Namespace migration: all classes moved under `RubyAsterisk::` (#46).

### Fixed

- Ruby 3.1 compatibility: `IO#timeout` / `IO#timeout=` shim in `lib/ruby-asterisk/compat.rb`; the `async` gem's Fiber scheduler calls `io.timeout` in Ruby 3.2+ — returning `nil` on 3.1 disables that code path without breaking async I/O (#55).
- Deterministic teardown on `AMI::Client#disconnect`: both reactor threads are joined and every pending `Promise` is rejected instead of being left dangling (#50, #79).
- A caller-supplied `action_id:` (`status`, `extension_state`) is now used as the request's ActionID instead of being appended as a second `ActionID` header, which left the response uncorrelated with its `Promise`.
- `wait_event(timeout: -1)` no longer imposes a 5 s deadline on the returned `Promise`: a negative Timeout means Asterisk waits indefinitely, so `#value` now does too.

### Removed

- `Net::Telnet` dependency (replaced by a raw `TCPSocket` owned by the AMI `Reactor`).

---

## [0.1.0]

Legacy AMI client based on `Net::Telnet`. Supported: login, originate, hangup, queue operations, ConfBridge, extension state, SIP peers, device state, monitor/record, parked calls, skinny devices.

> Earlier history: see `git log v0.1.0` or the [full commit list on GitHub](https://github.com/emilianodellacasa/ruby-asterisk/commits/master).
