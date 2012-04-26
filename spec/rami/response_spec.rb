# encoding: utf-8
require 'spec_helper'
describe Rami::Response do

	def core_show_channels_response
		"Event: CoreShowChannel
		ActionID: 839
		Channel: SIP/195.62.226.4-00000025
		UniqueID: 1335448133.61
		Context: incoming
		Extension: s
		Priority: 1
		ChannelState: 6
		ChannelStateDesc: Up
		Application: Parked Call
		ApplicationData:
		CallerIDnum: 3335313510
		CallerIDname:
		ConnectedLineNum:
		ConnectedLineName:
		Duration: 00:00:05
		AccountCode:
		BridgedChannel:
		BridgedUniqueID:"
	end


	describe ".new" do
		
		describe "receiving a Core Show Channels request" do
			it "should parse correctly data coming from Asterisk about channels" do 
				@response = Rami::Response.new("CoreShowChannels",core_show_channels_response)
				@response.data[:channels].should_not be_empty
			end

			it "should correctly fill the fields" do
        @response = Rami::Response.new("CoreShowChannels",core_show_channels_response)
        @response.data[:channels][0]["CallerIDnum"].should eq("3335313510")
      end
		end
		
	end
end
