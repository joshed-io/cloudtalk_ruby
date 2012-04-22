require 'bundler'
require 'rspec/core/rake_task'

desc "Run specs"
RSpec::Core::RakeTask.new do |t|
    t.rspec_opts = %w( --colour --format progress )
      t.pattern = 'spec/**/*_spec.rb'
end

task :default => :spec

