# frozen_string_literal: true

require 'spec_helper'
require 'ruby-asterisk/agi/protocol'

RSpec.describe RubyAsterisk::AGI::Protocol do
  describe '.parse_response' do
    subject(:parse) { described_class.parse_response(line) }

    context 'with a plain success result' do
      let(:line) { '200 result=1' }

      it { expect(parse).to eq(code: 200, result: '1', data: nil) }
    end

    context 'with result=0' do
      let(:line) { '200 result=0' }

      it { expect(parse).to eq(code: 200, result: '0', data: nil) }
    end

    context 'with endpos extra data' do
      let(:line) { '200 result=0 endpos=12345' }

      it { expect(parse).to eq(code: 200, result: '0', data: 'endpos=12345') }
    end

    context 'with parenthetical extra data' do
      let(:line) { '200 result=1 (some text)' }

      it { expect(parse).to eq(code: 200, result: '1', data: 'some text') }
    end

    context 'with trailing newline' do
      let(:line) { "200 result=1\n" }

      it { expect(parse[:code]).to eq(200) }
      it { expect(parse[:result]).to eq('1') }
    end

    context 'with 510 error' do
      let(:line) { '510 Invalid or unknown command' }

      it { expect(parse).to eq(code: 510, result: nil, data: 'Invalid or unknown command') }
    end

    context 'with 511 error' do
      let(:line) { '511 Command Not Permitted on a dead channel' }

      it { expect(parse).to eq(code: 511, result: nil, data: 'Command Not Permitted on a dead channel') }
    end

    context 'with nil (socket EOF)' do
      let(:line) { nil }

      it { expect(parse).to eq(code: 0, result: nil, data: 'Connection closed') }
    end

    context 'with an unrecognised line' do
      let(:line) { 'INVALID' }

      it { expect(parse[:code]).to eq(0) }
    end
  end
end
