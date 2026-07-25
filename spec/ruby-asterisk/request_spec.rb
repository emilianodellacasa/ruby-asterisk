# frozen_string_literal: true

require 'spec_helper'
describe RubyAsterisk::Request do
  describe 'of type Originate' do
    it 'should set a Variable option if set' do
      request = RubyAsterisk::Request.new('Originate', { 'Channel' => '1234', 'Context' => 'test', 'Exten' => '1', 'Priority' => '1', 'Callerid' => '1234', 'Timeout' => '30000', 'Variable' => 'var1=15' })
      request.commands.include?("Variable: var1=15\r\n").should_not be_nil
    end

    it 'should not set a Variable option if not set' do
      request = RubyAsterisk::Request.new('Originate', { 'Channel' => '1234', 'Context' => 'test', 'Exten' => '1', 'Priority' => '1', 'Callerid' => '1234', 'Timeout' => '30000', 'Variable' => nil })
      request.commands.include?('Variable: var=15').should == false
    end
  end

  describe 'action_id' do
    it 'generates one when none is supplied' do
      request = RubyAsterisk::Request.new('Ping')

      expect(request.action_id).not_to be_empty
      expect(request.commands.join).to include("ActionID: #{request.action_id}\r\n")
    end

    it 'uses the supplied action_id' do
      request = RubyAsterisk::Request.new('Status', {}, action_id: 'my-own-id')

      expect(request.action_id).to eq('my-own-id')
    end

    it 'emits exactly one ActionID header' do
      request = RubyAsterisk::Request.new('Status', { 'Channel' => 'SIP/alice' }, action_id: 'my-own-id')

      expect(request.commands.join.scan(/^ActionID:/).size).to eq(1)
    end
  end
end
