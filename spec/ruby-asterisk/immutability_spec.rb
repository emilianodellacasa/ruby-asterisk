# frozen_string_literal: true

require 'spec_helper'

describe 'Immutability for Ractor safety' do
  describe RubyAsterisk::Request do
    subject { RubyAsterisk::Request.new('Originate', { 'Channel' => '1234', 'Context' => 'test' }) }

    it 'is frozen' do
      subject.should be_frozen
    end

    it 'has a frozen action' do
      subject.action.should be_frozen
    end

    it 'has a frozen action_id' do
      subject.action_id.should be_frozen
    end

    it 'has a frozen parameters hash' do
      subject.parameters.should be_frozen
    end

    it 'has frozen parameter keys and values' do
      subject.parameters.each do |key, value|
        key.should be_frozen
        value.should be_frozen
      end
    end

    it 'raises FrozenError when attempting to modify instance variables' do
      -> { subject.instance_variable_set(:@action, 'Login') }.should raise_error(FrozenError)
    end

    it 'raises FrozenError when attempting to modify parameters' do
      -> { subject.parameters['NewKey'] = 'val' }.should raise_error(FrozenError)
    end

    it 'does not expose writer methods' do
      subject.respond_to?(:action=).should be false
      subject.respond_to?(:parameters=).should be false
      subject.respond_to?(:action_id=).should be false
    end

    it 'does not expose response_data' do
      subject.respond_to?(:response_data).should be false
      subject.respond_to?(:response_data=).should be false
    end

    it 'is Ractor-shareable' do
      Ractor.shareable?(subject).should be true
    end
  end

  describe RubyAsterisk::Response do
    let(:raw_response) do
      "Response: Success\nActionID: 123\nMessage: Authentication accepted\n\n"
    end
    subject { RubyAsterisk::Response.new('Login', raw_response) }

    it 'is frozen' do
      subject.should be_frozen
    end

    it 'has a frozen type' do
      subject.type.should be_frozen
    end

    it 'has a frozen action_id' do
      subject.action_id.should be_frozen
    end

    it 'has a frozen message' do
      subject.message.should be_frozen
    end

    it 'has a frozen raw_response' do
      subject.raw_response.should be_frozen
      subject.raw_response.each do |element|
        element.should be_frozen
      end
    end

    it 'has frozen data' do
      subject.data.should be_frozen
    end

    it 'raises FrozenError when attempting to modify instance variables' do
      -> { subject.instance_variable_set(:@type, 'Other') }.should raise_error(FrozenError)
    end

    it 'does not expose writer methods' do
      subject.respond_to?(:type=).should be false
      subject.respond_to?(:action_id=).should be false
      subject.respond_to?(:message=).should be false
      subject.respond_to?(:data=).should be false
      subject.respond_to?(:raw_response=).should be false
    end

    it 'is Ractor-shareable' do
      Ractor.shareable?(subject).should be true
    end

    context 'with parsed data containing nested structures' do
      let(:raw_response) do
        "Event: CoreShowChannel\nActionID: 839\nChannel: SIP/test\nCallerIDnum: 123\n\n" \
          "Event: CoreShowChannelsComplete\nActionID: 839\n\n"
      end
      subject { RubyAsterisk::Response.new('CoreShowChannels', raw_response) }

      it 'has deeply frozen data structures' do
        subject.data.should be_frozen
        subject.data[:channels].should be_frozen
        subject.data[:channels].each do |channel|
          channel.should be_frozen
          channel.each do |key, value|
            key.should be_frozen
            value.should be_frozen
          end
        end
      end

      it 'raises FrozenError when attempting to modify nested data' do
        -> { subject.data[:channels] << {} }.should raise_error(FrozenError)
      end
    end
  end

  describe RubyAsterisk::ResponseBuilder do
    it 'builds a frozen Response' do
      builder = RubyAsterisk::ResponseBuilder.new
      builder.type = 'Login'
      builder.raw_response = "Response: Success\nActionID: 123\n\n"
      response = builder.build
      response.should be_frozen
    end

    it 'raises ArgumentError when type is missing' do
      builder = RubyAsterisk::ResponseBuilder.new
      builder.raw_response = "Response: Success\n\n"
      -> { builder.build }.should raise_error(ArgumentError, 'type is required')
    end

    it 'raises ArgumentError when raw_response is missing' do
      builder = RubyAsterisk::ResponseBuilder.new
      builder.type = 'Login'
      -> { builder.build }.should raise_error(ArgumentError, 'raw_response is required')
    end

    it 'is not frozen itself' do
      builder = RubyAsterisk::ResponseBuilder.new
      builder.should_not be_frozen
    end
  end
end
