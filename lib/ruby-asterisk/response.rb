module RubyAsterisk
  ##
  #
  # Class for parsing response coming from Asterisk
  #
  class Response
    attr_accessor :type, :action_id, :message, :data, :raw_response

    DESCRIPTIVE_STATUS = {
      '-1' => 'Extension not found',
      '0' => 'Idle',
      '1' => 'In Use',
      '2' => 'Busy',
      '3' => 'Unavailable',
      '4' => 'Ringing',
      '5' => 'On Hold'
    }

    PARSE_DATA = {
      'CoreShowChannels' => {
        :symbol => :channels,
        :search_for => 'Event: CoreShowChannel',
        :stop_with => 'Event: CoreShowChannelsComplete'
      },
      'ParkedCalls' => {
        :symbol => :calls,
        :search_for => 'Event: ParkedCall',
        :stop_with => nil
      },
      'Originate'  => {
        :symbol => :dial,
        :search_for => 'Event: Dial',
        :stop_with => nil
      },
      'MeetMeList'  => {
        :symbol => :rooms,
        :search_for => 'Event: MeetmeList',
        :stop_with => nil
      },
      'Status'  => {
        :symbol => :status,
        :search_for => 'Event: Status',
        :stop_with => nil
      },
      'ExtensionState'  => {
        :symbol => :hints,
        :search_for => 'Response:',
        :stop_with => nil
      },
      'SKINNYdevices'  => {
        :symbol => :skinnydevs,
        :search_for => 'Event: DeviceEntry',
        :stop_with => nil
      },
      'SKINNYlines' => {
        :symbol => :skinnylines,
        :search_for => 'Event: LineEntry',
        :stop_with => nil
      },
      'QueuePause' => {
        :symbol => :queue_pause,
        :search_for => 'Response:',
        :stop_with => nil
      },
      'Pong' => {
        :symbol => :pong,
        :search_for => 'Response:',
        :stop_with => nil
      },
      'Events' => {
        :symbol => :event_mask,
        :search_for => 'Ping:',
        :stop_with => nil
      },
      'SIPpeers' => {
        :symbol => :peers,
        :search_for => 'Event: PeerEntry',
        :stop_with => nil
      },
    }

    def initialize(type,response)
      self.raw_response = response
      self.type = type
      self.action_id = self._parse_action_id
      self.message = self._parse_message
      self.data = self._parse_response
    end

    def success
      self.raw_response.include?("Response: Success")
    end

    protected

    def _parse_action_id
      self._parse("ActionID:")
    end

    def _parse_message
      self._parse("Message:")
    end

    def _parse(field)
      _value = nil
      self.raw_response.each_line do |line|
        if line.start_with?(field)
          _value = line[line.rindex(":")+1..line.size].strip
        end
      end
      _value
    end

    def _parse_response
      if PARSE_DATA.include?(self.type)
        self._parse_objects(self.raw_response, PARSE_DATA[self.type])
      else
        self.raw_response
      end
    end

    def _convert_status(_data)
      _data[:hints].each do |hint|
        hint["DescriptiveStatus"] = DESCRIPTIVE_STATUS[hint["Status"]]
      end
      _data
    end

    def _parse_objects(response, parse_params)
       _data = { parse_params[:symbol] => [] }
      parsing = false
      object = nil
      response.each_line do |line|
        line.strip!
        if line.strip.empty? or (!parse_params[:stop_with].nil? and line.start_with?(parse_params[:stop_with]))
          parsing = false
        elsif line.start_with?(parse_params[:search_for])
          _data[parse_params[:symbol]] << object unless object.nil?
          object = {}
          parsing = true
        elsif parsing
          tokens = line.split(':', 2)
          object[tokens[0].strip]=tokens[1].strip unless tokens[1].nil?
        end
      end
      _data[parse_params[:symbol]] << object unless object.nil?
      _data = _convert_status(_data) if _data.include?(:hints)
      _data
    end
  end
end
