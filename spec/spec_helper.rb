# frozen_string_literal: true

require 'simplecov'
SimpleCov.start
require 'rubygems'
require 'bundler'

require 'ruby-asterisk'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = %i[should expect]
  end

  # Give a moment for all Ractors/Threads to be cleaned up before RSpec exits.
  # This can help prevent the GitHub Actions runner from prematurely killing
  # lingering processes and marking the job as "canceled".
  config.after(:suite) do
    puts "\n[CI] Waiting for background processes to terminate..."
    sleep 0.2
    puts '[CI] Done.'
  end
end
