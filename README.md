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

## Development

Questions or problems? Please post them on the [issue tracker](https://github.com/emilianodellacasa/rami/issues). You can contribute changes by forking the project and submitting a pull request. You can ensure the tests passing by running `bundle` and `rake`.

This gem is created by Emiliano Della Casa and is under the MIT License and it is distributed by courtesy of [Engim srl](http://www.engim.eu/en).

