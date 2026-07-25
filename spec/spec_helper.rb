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

  config.after(:suite) do
    puts '[CI] Done.'
  end
end
