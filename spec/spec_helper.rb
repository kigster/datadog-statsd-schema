# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter %r{^/spec/}
end

require "datadog/statsd/schema"
require "rspec/its"

Datadog::Statsd::Schema.in_test = true

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Load shared examples
Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

at_exit do
  `chmod -R 777 coverage`
end
