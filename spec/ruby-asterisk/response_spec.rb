# encoding: utf-8
require 'spec_helper'
describe RubyAsterisk::Response do

	def empty_core_show_channels_response
		"Event: CoreShowChannelsComplete
		EventList: Complete
    ListItems: 1
    ActionID: 839"
	end

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
		CallerIDnum: 123456
		CallerIDname:
		ConnectedLineNum:
		ConnectedLineName:
		Duration: 00:00:05
		AccountCode:
		BridgedChannel:
		BridgedUniqueID:

		Event: CoreShowChannelsComplete
		EventList: Complete
		ListItems: 1
		ActionID: 839"
	end

	def parked_calls_response
		"Event: ParkedCall
		Parkinglot: default
		Exten: 701
		Channel: SIP/195.62.226.2-00000026
		From: SIP/195.62.226.2-00000026
		Timeout: 3
		CallerIDNum: 123456
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

	def meet_me_list_response
		"Event: MeetmeList
		ActionID: 921
		Conference: 1234
		UserNumber: 1
		CallerIDNum: 123456
		CallerIDName: <no name>
		ConnectedLineNum: <unknown>
		ConnectedLineName: <no name>
		Channel: SIP/195.62.226.18-0000000e
		Admin: No
		Role: Talk and listen
		MarkedUser: No
		Muted: No
		Talking: Not monitored"
	end

	def extension_state_response
		"Response: Success
		ActionID: 180
		Message: Extension Status
		Exten: 9100
		Context: HINT
		Hint: SIP/9100
		Status: 0"
	end

	describe ".new" do
		
		describe "receiving a Core Show Channels request" do
			it "should parse correctly data coming from Asterisk about channels" do 
				@response = RubyAsterisk::Response.new("CoreShowChannels",core_show_channels_response)
				@response.data[:channels].should_not be_empty
			end

			it "should correctly fill the fields" do
        @response = RubyAsterisk::Response.new("CoreShowChannels",core_show_channels_response)
        @response.data[:channels][0]["CallerIDnum"].should eq("123456")
      end

			it "should have no channels if answer is empty" do
				@response = RubyAsterisk::Response.new("CoreShowChannels",empty_core_show_channels_response)
				@response.data[:channels].count.should eq(0)
			end
		end
	
		describe "receiving a Parked Calls request" do
			it "should parse correctly data coming from Asterisk about calls" do
				@response = RubyAsterisk::Response.new("ParkedCalls",parked_calls_response)
				@response.data[:calls].should_not be_empty
			end

			it "should correctly fill the fields" do
				@response = RubyAsterisk::Response.new("ParkedCalls",parked_calls_response)
				@response.data[:calls][0]["Exten"].should eq("701")
			end
		end

		describe "receiving a Originate request" do 
			it "should parse correctly data coming from Asterisk about the call" do
        @response = RubyAsterisk::Response.new("Originate",originate_response)
        @response.data[:dial].should_not be_empty
      end

      it "should correctly fill the fields" do
        @response = RubyAsterisk::Response.new("Originate",originate_response)
        @response.data[:dial][0]["UniqueID"].should eq("1335457364.68")
      end
    end
		
		describe "receiving a MeetMeList request" do
      it "should parse correctly data coming from Asterisk about the conference room" do
        @response = RubyAsterisk::Response.new("MeetMeList",meet_me_list_response)
        @response.data[:rooms].should_not be_empty
      end

      it "should correctly fill the fields" do
        @response = RubyAsterisk::Response.new("MeetMeList",meet_me_list_response)
        @response.data[:rooms][0]["Conference"].should eq("1234")
      end
    end

		describe "receiving a ExtensionState request" do
      it "should parse correctly data coming from Asterisk about the state of the extension" do
        @response = RubyAsterisk::Response.new("ExtensionState",extension_state_response)
        @response.data[:hints].should_not be_empty
      end

      it "should correctly fill the fields" do
        @response = RubyAsterisk::Response.new("ExtensionState",extension_state_response)
        @response.data[:hints][0]["Status"].should eq("0")
				@response.data[:hints][0]["DescriptiveStatus"].should eq("Idle")
      end
    end
	end
end
