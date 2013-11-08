require 'bundler'
Bundler::GemHelper.install_tasks

require 'rspec'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) 

require 'quality/rake/task'

Quality::Rake::Task.new

task default: :spec
