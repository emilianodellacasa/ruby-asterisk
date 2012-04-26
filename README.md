# RAMI

This gem add support to your Ruby or RubyOnRails projects to Asterisk Manager Interface

There was a project with the same name, but it appears to be discontinued so I decided to start a new project

## Installation

### Rails3

Add to your Gemfile and run the `bundle` command to install it.

```ruby
 gem "rami"
```

### Rails2

Simply run in your terminal

```ruby
 gem install rami
```

## Usage

### INITIALIZE

To create a new AMI session, just call the following command

```ruby
 @ami = Rami::Rami.new("192.168.1.1",5038)
```

### LOGIN

To log in, provide to the created sessions a valid username and password 

```ruby
 @ami.login("mark","mysecret")
```

Like all commands, it will return a Response command that could be parsed accordingly

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


### THE RESPONSE OBJECT

The response object contains all information about all data received from Asterisk. Here follows a list of all object's properties:

- type
- success
- action_id
- message
- data

The data property contains all additional information obtained from Asterisk, like for example the list of active channels after a "core show channels" command.

## Development

Questions or problems? Please post them on the [issue tracker](https://github.com/emilianodellacasa/rami/issues). You can contribute changes by forking the project and submitting a pull request. You can ensure the tests passing by running `bundle` and `rake`.

This gem is created by Emiliano Della Casa and is under the MIT License and it is distributed by courtesy of [Engim srl](http://www.engim.eu/en).

