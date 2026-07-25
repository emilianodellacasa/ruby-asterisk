# frozen_string_literal: true

# IO#timeout / IO#timeout= were added in Ruby 3.2.
# The async gem's Fiber Scheduler calls io.timeout inside io_wait to honour
# per-IO timeouts; returning nil disables that path on Ruby 3.1.
IO.define_method(:timeout) { nil } unless IO.method_defined?(:timeout)
IO.define_method(:timeout=) { |_| nil } unless IO.method_defined?(:timeout=)
