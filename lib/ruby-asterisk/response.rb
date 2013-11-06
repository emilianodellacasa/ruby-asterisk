module RubyAsterisk
  class Response
    attr_accessor :type, :success, :action_id, :message, :data, :response, :request

    def initialize(type,response,request=nil)
      self.request = request
      self.response = response
      self.type = type
      self.success = self._parse_successfull(response)
      self.action_id = self._parse_action_id(response)
      self.message = self._parse_message(response)
      self.data = self._parse_data(response)
    end

    protected

    def _parse_successfull(response)
      response.include?("Response: Success") or (self.type == "Command")
    end

    def _parse_action_id(response)
      _action_id = self._parse(response,"ActionID:")
    end

    def _parse_message(response)
      _message = self._parse(response,"Message:")
    end

    def _parse(response,field)
      _value = nil
      response.each_line do |line|
        if line.start_with?(field)
          _value = line[line.rindex(":")+1..line.size].strip
        end
      end
      _value
    end

    def _parse_command_data(response)
      return nil unless self.request
      case self.request.parameters["Command"]
      when "sip show peers"
        self._parse_sip_show_peers(response)
      else
        throw new ArgumentError("Command Not Supported")
      end
    end

    def _parse_sip_show_peers(response)
      start = response.index("\nName/username")+1
      res = response[(start)..(response.size-1)]
      users = res.split("\n").collect{|line| line.split("\s")}

      users[1..(users.size-3)]
    end

    def _parse_data(response)
      case self.type
        when "CoreShowChannels"
          self._parse_data_core_show_channels(response)
        when "ParkedCalls"
          self._parse_data_parked_calls(response)
        when "Originate"
          self._parse_originate(response)
        when "MeetMeList"
          self._parse_meet_me_list(response)
        when "ExtensionState"
          self._parse_extension_state(response)
        when "SKINNYdevices"
          self._parse_skinny_devices(response)
        when "SKINNYlines"
          self._parse_skinny_lines(response)
        when "Command"
          begin
            self._parse_command_data(response)
          rescue ArgumentError
            nil
          rescue
            nil
          end
        when "QueuePause"
          self._parse_queue_pause(response)
        when "Pong"
          self._parse_pong(response)
        when "Events"
          self._parse_event_mask(response)
      end

    end

    def _parse_meet_me_list(response)
      self._parse_objects(response,:rooms,"Event: MeetmeList")
    end

    def _parse_originate(response)
      self._parse_objects(response,:dial,"Event: Dial")
    end

    def _parse_data_parked_calls(response)
      self._parse_objects(response,:calls,"Event: ParkedCall")
    end

    def _parse_data_core_show_channels(response)
      self._parse_objects(response,:channels,"Event: CoreShowChannel","Event: CoreShowChannelsComplete")
    end

    def _parse_extension_state(response)
      _data = self._parse_objects(response,:hints,"Response:")
      self._convert_status(_data)
    end
    
    def _parse_skinny_devices(response)
      self._parse_objects(response,:skinnydevs,"Event: DeviceEntry")
    end

    def _parse_skinny_lines(response)
      self._parse_objects(response,:skinnylines,"Event: LineEntry")
    
    def _parse_queue_pause(response)
      _data = self._parse_objects(response,:queue_pause,"Response:")
    end
    
    def _parse_pong(response)
      _data = self._parse_objects(response,:pong, "Response:")
    end
    
    def _parse_event_mask(response)
      _data = self._parse_objects(response, :event_mask, "Ping:")
    end

    def _convert_status(_data)
      _data[:hints].each do |hint|
        case hint["Status"]
          when "-1"
            hint["DescriptiveStatus"] = "Extension not found"
          when "0"
            hint["DescriptiveStatus"] = "Idle"
          when "1"
            hint["DescriptiveStatus"] = "In Use"
          when "2"
            hint["DescriptiveStatus"] = "Busy"
          when "4"
            hint["DescriptiveStatus"] = "Unavailable"
          when "8"
            hint["DescriptiveStatus"] = "Ringing"
          when "16"
            hint["DescriptiveStatus"] = "On Hold"
        end
      end
      _data
    end

    def _parse_objects(response,symbol_name,search_for,stop_with=nil)
       _data = { symbol_name => [] }
      parsing = false
      object = nil
      response.each_line do |line|
        if line.strip.empty? or (!stop_with.nil? and line.start_with?(stop_with))
          parsing = false
        elsif line.start_with?(search_for)
          _data[symbol_name] << object unless object.nil?
          object = {}
          parsing = true
        elsif parsing
          tokens = line.split(':', 2)
          object[tokens[0].strip]=tokens[1].strip unless tokens[1].nil?
        end
      end
      _data[symbol_name] << object unless object.nil?
      _data
    end
  end
end
