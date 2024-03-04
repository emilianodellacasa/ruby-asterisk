# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "ruby-asterisk/version"

Gem::Specification.new do |s|
  s.name        = "ruby-asterisk"
  s.version     = Rami::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Emiliano Della Casa"]
  s.email       = ["emiliano.dellacasa@gmail.com"]
  s.homepage    = "http://github.com/emilianodellacasa/ruby-asterisk"
  s.summary     = %q{Asterisk Manager Interface in Ruby}
  s.description = %q{Add support to your ruby or rails projects to Asterisk Manager Interface (AMI)}
  s.licenses    = ['MIT']

  s.rubyforge_project = "ruby-asterisk"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency('net-telnet')

  s.add_development_dependency "rake"
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'quality'
end
