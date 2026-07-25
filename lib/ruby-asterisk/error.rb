# frozen_string_literal: true

module RubyAsterisk
  class Error < StandardError; end

  # Raised when Asterisk sends an out-of-band `HANGUP` line mid-command
  # (the channel was hung up). Callers may rescue this to abort cleanly
  # instead of receiving a bogus response and desynchronizing the stream.
  class HangupError < Error; end
end
