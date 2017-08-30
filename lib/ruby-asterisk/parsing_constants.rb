##
#
# File containing parsing constants
#
module RubyAsterisk
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
    'ConfbridgeListRooms'  => {
      :symbol => :rooms,
      :search_for => 'Event: ConfbridgeListRooms',
      :stop_with => nil
    },
    'ConfbridgeList'  => {
      :symbol => :channels,
      :search_for => 'Event: ConfbridgeList',
      :stop_with => nil
    },
    'Status'  => {
      :symbol => :status,
      :search_for => 'Event: Status',
      :stop_with => nil
    },
    'ExtensionState'  => {
      :symbol => :hints,
      :search_for => 'Response: Success',
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
end
