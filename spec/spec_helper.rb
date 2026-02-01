require 'simplecov'
SimpleCov.start
require 'rubygems'
require 'bundler'

require 'ruby-asterisk'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :should
  end

  config.before(:each) do
    @telnet_session = double('Net::Telnet')
    allow(@telnet_session).to receive(:close)
    allow(Net::Telnet).to receive(:new).and_return(@telnet_session)
    allow(Net::Telnet).to receive(:new).with('Host' => '127.0.0.1', 'Port' => 666, 'Timeout' => 10).and_raise(StandardError)

    @commands = []
    allow(@telnet_session).to receive(:write) do |string|
      @commands << string
    end

    allow(@telnet_session).to receive(:waitfor) do |&block|
      full_command = @commands.join
      @commands = [] # reset for next command

      response = if full_command.include?("Action: Login")
        if full_command.include?("Secret: mysecret")
          "Response: Success\nActionID: 123\nMessage: Authentication accepted\n\n"
        elsif full_command.include?("Secret: wrong")
          "Response: Error\nActionID: 123\nMessage: Authentication failed\n\n"
        end
      else
        "Response: Success\nActionID: 123\n\n"
      end
      block.call(response) if response
    end
  end
end