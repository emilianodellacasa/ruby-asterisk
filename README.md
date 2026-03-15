# RUBY-ASTERISK

[![Maintainability](https://api.codeclimate.com/v1/badges/2861728929db934eb376/maintainability)](https://codeclimate.com/github/emilianodellacasa/ruby-asterisk/maintainability)

This gem adds support to your Ruby or RubyOnRails projects to Asterisk Manager Interface (AMI).

**Note:** Version 0.2.0+ uses **Ruby Ractors** for non-blocking I/O and requires **Ruby 3.1+**.

## Installation

Add to your Gemfile and run the `bundle` command to install it.

```ruby
 gem "ruby-asterisk"
```

## Usage

### INITIALIZE

To create a new AMI session, just call the following command:

```ruby
 require 'ruby-asterisk'
 
 # Create a client instance (uses Ractor for async reading)
 @ami = RubyAsterisk::AMI::Client.new(host: "192.168.1.1", port: 5038)
 
 # Connect explicitly (starts the Ractor)
 @ami.connect
```

### LOGIN

To log in, provide to the created sessions a valid username and password 

```ruby
 @ami.login(username: "mark", secret: "mysecret")
```

Like all commands, it will return a Response object that could be parsed accordingly.

### CORE SHOW CHANNELS

To get a list of all channels currently active on your Asterisk installation, use the following command

```ruby
 @ami.core_show_channels
```

### PARKED CALLS

To get a list of all parked calls on your Asterisk PBX, use the following command

```ruby
 @ami.parked_calls
```

### ORIGINATE

To start a new call use the following command

```ruby
 @ami.originate("SIP/9100","OUTGOING","123456","1", variable: "var1=12,var2=99") # CHANNEL, CONTEXT, CALLEE, PRIORITY, VARIABLES
```


### COMMAND

To execute a cli command use the following code

```ruby
 @ami.command("core show channels")
```

### MEETME LIST

To get a list of all active conferences use the following command

```ruby
 @ami.meet_me_list
```

### EXTENSION STATE

To get the state of an extension use the following command

```ruby
 @ami.extension_state(exten: @exten, context: @context)
```

### DEVICE STATE LIST

To get list of states of devices

```ruby
 @ami.device_state_list
```

### SKINNY DEVICES AND LINES

To get list of skinny devices

```ruby
 @ami.skinny_devices
```

To get list of skinny lines

```ruby
 @ami.skinny_lines
```

### QUEUE PAUSE
                                                                                         
To pause or unpause a member in a call queue
                                                                                                        
```ruby
 @ami.queue_pause(interface: "SIP/100", paused: "true", queue: "myqueue", reason: "reason")                                                                            
```

### PING

To ping asterisk AMI

```ruby
 @ami.ping
```

### EVENT MASK                                                            

To enable or disable sending events to this manager connection

```ruby
 @ami.event_mask("on")
```

### SIPpeers

To get a list of sip peers (equivalent to "sip show peers" call on the asterisk server).  This can be used to get a buddy list. 

```ruby
 @ami.sip_peers
```

### SIP SHOW PEER

To get info of a peer (equivalent to "sip show peer" call on the asterisk server).

```ruby
 @ami.sip_show_peer(peer)
```

### SIP SHOW REGISTRY

Retrieve a status of SIP registries and their statuses from the Asterisk server.

```ruby
 @ami.sip_show_registry
```

### STATUS
                                                                                                                        
To get a status of a single channel or for all channels                                                                                                                                  
```ruby
 @ami.status 
```

### ATXFER

Attendand transfer

```ruby
 @ami.atxfer(channel: channel, exten: exten, context: context, priority: '1')
```

### WAIT EVENT

Wait for an event to occur. Timeout in seconds to wait for events, -1 means forever

```ruby
 @ami.wait_event(timeout: -1)
```

### MONITOR

Monitor a channel

```ruby
 @ami.monitor(channel, mix: false, file: nil, format: 'wav')
```

### STOP MONITOR

Stop monitoring a channel

```ruby
 @ami.stop_monitor(channel)
```

### PAUSE MONITOR

Pause monitoring of a channel

```ruby
 @ami.pause_monitor(channel)
```

### UNPAUSE MONITOR

Unpause monitoring of a channel

```ruby
 @ami.unpause_monitor(channel)
```

### CHANGE MONITOR

Change monitoring filename of a channel

```ruby
 @ami.change_monitor(channel: channel, file: file)
```

### DISCONNECT

To close the connection and stop the Ractor:

```ruby
 @ami.disconnect
```

### THE RESPONSE OBJECT

The response object contains all information about all data received from Asterisk. Here follows a list of all object's properties:

- type
- success
- action_id
- message
- data
- raw_response

The data property contains all additional information obtained from Asterisk, like for example the list of active channels after a "core show channels" command.

## ARI (Asterisk REST Interface)

Version 0.3.0+ adds an HTTP client for the [Asterisk REST Interface (ARI)](https://wiki.asterisk.org/wiki/display/AST/Getting+Started+with+ARI), which provides fine-grained, real-time call control via a REST API.

### INITIALIZE ARI CLIENT

```ruby
require 'ruby-asterisk'

client = RubyAsterisk::ARI::Client.new(
  'http://192.168.1.1:8088', # ARI base URL
  'my_api_key',              # ARI API key (username; password is empty by default)
  'my_stasis_app'            # Stasis application name
)
```

### ASTERISK INFO

```ruby
info = client.asterisk_info
# => Hash with build, system, config, status sections
puts info['system']['version']
```

### CHANNELS

Fetch a single channel by ID:

```ruby
channel = client.channels.get('1553112062.1')
puts channel.id          # => "1553112062.1"
puts channel.data['name'] # => "PJSIP/alice-00000001"
```

List all active channels:

```ruby
channels = client.channels.list
channels.each { |ch| puts ch.data['name'] }
```

Call control actions on a channel:

```ruby
channel.ring     # send ringing indication
channel.answer   # answer the call
channel.play('sound:hello-world')              # play audio
channel.play('sound:tt-monkeys', playbackId: 'pb-1') # play with options
channel.hangup   # hang up and destroy the channel
```

### BRIDGES

Create or fetch a bridge, then mix channels into it:

```ruby
# List all bridges
bridges = client.bridges.list

# Fetch a specific bridge by ID
bridge = client.bridges.get('my-bridge-id')

# Add a channel to the bridge
bridge.add_channel('1553112062.1')

# Remove a channel from the bridge
bridge.remove_channel('1553112062.1')

# Destroy the bridge
bridge.destroy
```

### PLAYBACKS

Control in-progress media playbacks:

```ruby
playback = client.playbacks.get('pb-1')

playback.control('pause')    # pause media
playback.control('unpause')  # resume media
playback.control('restart')  # restart from beginning
playback.stop                # stop and destroy the playback
```

### ENDPOINTS

Inspect registered endpoints:

```ruby
endpoints = client.endpoints.list
endpoints.each do |ep|
  puts "#{ep.technology}/#{ep.resource} — #{ep.state}"
end
# => PJSIP/alice — online
# => PJSIP/bob   — offline
```

### ERROR HANDLING

All ARI methods raise `RubyAsterisk::Error` on HTTP 4xx/5xx responses:

```ruby
begin
  channel = client.channels.get('nonexistent-id')
rescue RubyAsterisk::Error => e
  puts e.message  # => "Channel not found"
end
```

## Development

Questions or problems? Please post them on the [issue tracker](https://github.com/emilianodellacasa/ruby-asterisk/issues). You can contribute changes by forking the project and submitting a pull request. You can ensure the tests passing by running `bundle` and `rake`.

This gem is created by Emiliano Della Casa and is under the MIT License and it is distributed by courtesy of [Engim srl](http://www.engim.eu/en).
