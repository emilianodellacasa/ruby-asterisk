# encoding: utf-8
require 'spec_helper'
describe Rami do

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

	def mock_request(stubs={})
    (@mock_request ||= mock_model(Rami::Request).as_null_object).tap do |request|
      request.stub(stubs) unless stubs.empty?
    end
  end

	before :each do
		@session = Rami::Rami.new("127.0.0.1",5038)
  end

	after :each do
		@session.disconnect
	end

	describe ".new" do
		it "initialize session with host" do
			@session.host.should eq("127.0.0.1")
		end

		it "initialize session with host" do
      @session.port.should eq(5038)
    end

		it "should start the session as disconnected" do
			@session.connected.should_not be_true
		end
	end 

	describe ".connect" do
		it "should return true if everything is ok" do
			@session.connect.should be_true
		end

		it "should return false if everything if something went wrong" do
			@session.port = 666
      @session.connect.should_not be_true
			@session.port = 5038
    end

		it "should change state to session as connected" do
			@session.connect
			@session.connected.should be_true
		end
	end

	describe ".disconnect" do
    it "should return true if everything is ok" do
      @session.disconnect.should be_true
    end

		it "should change state to session as disconnected" do
      @session.disconnect
      @session.connected.should_not be_true
    end
  end

	describe ".login" do
		it "should return a response object" do
			@session.login("mark","mysecret").should be_kind_of(Rami::Response)
		end

		it "should return a response with type Login" do
			@session.login("mark","mysecret").type.should eq("Login")
		end

		describe "if everything is ok" do
			it "should return a successfull response" do
				@session.login("mark","mysecret").success.should be_true
			end

			it "should fill the ActionID" do
        @session.login("mark","mysecret").action_id.should_not be_nil
      end

			it "should fill the Message" do
        @session.login("mark","mysecret").message.should_not be_nil
      end
		end

		describe "if credentials are wrong" do
			it "should not return a successfull response" do
				@session.login("mark","wrong").success.should be_false
			end
		end
	end

	describe ".core_show_channels" do
    it "should return a response object" do
			@session.login("mark","mysecret")
      @session.core_show_channels.should be_kind_of(Rami::Response)
    end

		it "should contain additional data about channels" do
			@session.login("mark","mysecret")
			@session.core_show_channels.data[:channels].should_not be_nil
		end 
	end

	describe ".parked_calls" do
    it "should return a response object" do
      @session.login("mark","mysecret")
      @session.parked_calls.should be_kind_of(Rami::Response)
    end

    it "should contain additional data about parked calls" do
      @session.login("mark","mysecret")
      @session.parked_calls.data[:calls].should_not be_nil
    end
  end

	describe ".originate" do
		it "should return a response object" do
			@session.login("mark","mysecret")
			@session.originate("SIP/9100","OUTGOING","123456","1").should be_kind_of(Rami::Response)
		end
	end
end
