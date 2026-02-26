# frozen_string_literal: true

require 'simplecov'
SimpleCov.start
require 'rubygems'
require 'bundler'

require 'ruby-asterisk'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end

  # Remove legacy Net::Telnet mocks as we moved to Ractor based implementation
  # config.before(:each) do
  #   ...
  # end
end
