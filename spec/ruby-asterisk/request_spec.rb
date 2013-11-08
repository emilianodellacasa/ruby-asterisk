# encoding: utf-8
require 'spec_helper'
describe RubyAsterisk::Request do

  describe "of type Originate" do
    it "should set a Variable option if set" do
      request = RubyAsterisk::Request.new("Originate",{"Channel" => "1234", "Context" => "test", "Exten" => "1", "Priority" => "1", "Callerid" => "1234", "Timeout" => "30000", "Variable" => "var1=15"  })
      request.commands.include?("Variable: var1=15\r\n").should_not be_nil
    end

    it "should not set a Variable option if not set" do
      request = RubyAsterisk::Request.new("Originate",{"Channel" => "1234", "Context" => "test", "Exten" => "1", "Priority" => "1", "Callerid" => "1234", "Timeout" => "30000", "Variable" => nil  })
      request.commands.include?("Variable: var=15").should==false
    end
  end
end

