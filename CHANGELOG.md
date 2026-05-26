# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **AMI async reactor** — replaced the experimental Ractor pipeline (`SocketReaderRactor` + `ParserRactor` + event-loop Thread) with a single `Async` reactor running in a dedicated OS thread. Two cooperative Fibers (intake + reader) handle socket I/O; a pure `Parser` module handles frame parsing. Public `Client` API is unchanged; `Promise` (Mutex+CV) is unchanged. Unifies the concurrency runtime with AGI (both now use the `async` gem). Removes experimental Ractor warnings, CI GC workarounds, and the `sleep 0.2` suite teardown.

## [1.0.0] - 2026-05-12

### Added

- **AGI::Protocol** — stateless module for AGI wire protocol: `format_command`, `escape_argument`, `quote`, `parse_response`, `error?` (#55)
- **AGI::Protocol env helpers** — `parse_env_line`, `parse_env_block`, `collect_multiline_error` for robust Asterisk environment parsing and 520 multi-line error handling (#56)
- **AGI::Session** — full FastAGI session wrapper with fiber-friendly socket I/O: `answer`, `hangup`, `stream_file`, `say_digits`, `say_number`, `exec`, `set_variable`, `get_variable`, `get_data`, `verbose`, `dial`, `wait_for_digit`, `record_file`, `send_text`, `send_image`, `channel_status`, `database_get/put/del/deltree` (#55)
- **AGI::Server** — FastAGI TCP server backed by Async + Fiber scheduler; each connection runs in its own Fiber sharing a single OS thread (#54)
- **ARI::WebSocket** — WebSocket client for ARI real-time events: per-event callbacks via `on(type, &block)`, auto-reconnect, configurable ping keep-alive (#53)
- **ARI::Client** — HTTP client for the Asterisk REST Interface backed by Faraday (#51)
- **ARI::Resources** — Channel, Bridge, Playback, Endpoint, Collection, and Base resource classes for the ARI HTTP client (#52)
- **AMI::Client async rewrite** — non-blocking AMI client using `SocketReaderRactor` + `ParserRactor` + `Promise`-based responses; every command returns a `Promise`, call `.value(timeout)` to materialise the `Response` (#48, #49, #50)
- **AMI command modules** — Channel, Conference, Extension, Mailbox, Monitor, Queue, Sip, System extracted into dedicated modules and mixed into `AMI::Client` (#47)
- `logoff` method on `AMI::Client`

### Changed

- **BREAKING:** `RubyAsterisk::AMI::Client` replaces the legacy flat `RubyAsterisk::AMI` class; every command now returns `RubyAsterisk::AMI::Promise` instead of a synchronous `Response`.
- **BREAKING:** `Rami::VERSION` renamed to `RubyAsterisk::VERSION`; callers reading `Rami::VERSION` will get a `NameError`.
- Minimum Ruby version set to 3.1.
- Immutable domain objects (`Request`, `Response`) are now deep-frozen (#45).
- Namespace migration: all classes moved under `RubyAsterisk::` (#46).

### Fixed

- Ruby 3.1 compatibility: `IO#timeout` / `IO#timeout=` shim added at the top of `agi/server.rb`; the `async` gem's Fiber scheduler calls `io.timeout` in Ruby 3.2+ — returning `nil` on 3.1 disables that code path without breaking async I/O (#55).
- Robust Ractor cleanup and error handling on `AMI::Client#disconnect` (#50).

### Removed

- `Net::Telnet` dependency (replaced by raw `TCPSocket` via Ractor pipeline).

---

## [0.1.0]

Legacy AMI client based on `Net::Telnet`. Supported: login, originate, hangup, queue operations, ConfBridge, extension state, SIP peers, device state, monitor/record, parked calls, skinny devices.

> Earlier history: see `git log v0.1.0` or the [full commit list on GitHub](https://github.com/emilianodellacasa/ruby-asterisk/commits/master).
