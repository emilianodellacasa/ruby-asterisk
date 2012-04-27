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

	def parked_calls_response
		"Event: ParkedCall
		Parkinglot: default
		Exten: 701
		Channel: SIP/195.62.226.2-00000026
		From: SIP/195.62.226.2-00000026
		Timeout: 3
		CallerIDNum: 3335313510
		CallerIDName:
		ConnectedLineNum:
		ConnectedLineName:
		ActionID: 899"
	end

	def originate_response
		"Event: Dial
		Privilege: call,all
		SubEvent: End
		Channel: SIP/9100-0000002b
		UniqueID: 1335457364.68
		DialStatus: CHANUNAVAIL"
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
	
		describe "receiving a Parked Calls request" do
			it "should parse correctly data coming from Asterisk about calls" do
				@response = Rami::Response.new("ParkedCalls",parked_calls_response)
				@response.data[:calls].should_not be_empty
			end

			it "should correctly fill the fields" do
				@response = Rami::Response.new("ParkedCalls",parked_calls_response)
				@response.data[:calls][0]["Exten"].should eq("701")
			end
		end

		describe "resceiving a Originate request" do 
			it "should parse correctly data coming from Asterisk about the call" do
        @response = Rami::Response.new("Originate",originate_response)
        @response.data[:dial].should_not be_empty
      end

      it "should correctly fill the fields" do
        @response = Rami::Response.new("Originate",originate_response)
        @response.data[:dial][0]["UniqueID"].should eq("1335457364.68")
      end
    end
	end
end
