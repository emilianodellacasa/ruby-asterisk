# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'ruby-asterisk/version'

Gem::Specification.new do |s|
  s.name        = 'ruby-asterisk'
  s.version     = Rami::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Emiliano Della Casa']
  s.email       = ['emiliano.dellacasa@gmail.com']
  s.homepage    = 'http://github.com/emilianodellacasa/ruby-asterisk'
  s.summary     = 'Asterisk Manager Interface in Ruby'
  s.description = 'Add support to your ruby or rails projects to Asterisk Manager Interface (AMI)'
  s.licenses    = ['MIT']
  s.required_ruby_version = '>= 3.1'

  s.files         = `git ls-files`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.require_paths = ['lib']

  s.add_runtime_dependency 'faraday', '>= 1.0'
  s.add_runtime_dependency 'faye-websocket', '~> 0.11'

  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rubocop-performance'
  s.add_development_dependency 'simplecov'
  s.metadata['rubygems_mfa_required'] = 'true'
end
