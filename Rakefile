# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "timeout"

def shell(*args)
  puts "running: #{args.join(" ")}"
  system(args.join(" "))
end

task :clean do
  shell("rm -rf pkg/ tmp/ coverage/ doc/ ")
end

task gem: [:build] do
  shell("gem install pkg/*")
end

task permissions: [:clean] do
  shell("chmod -v o+r,g+r * */* */*/* */*/*/* */*/*/*/* */*/*/*/*/*")
  shell("find . -type d -exec chmod o+x,g+x {} \\;")
end

task build: :permissions

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:rubocop)

# Define the default task to include both
task default: %i[spec rubocop]
