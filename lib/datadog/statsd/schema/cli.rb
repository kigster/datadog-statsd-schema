# frozen_string_literal: true

require "dry/cli"
require_relative "commands"

module Datadog
  class Statsd
    module Schema
      module CLI
        extend Dry::CLI::Registry

        register "analyze", Commands::Analyze
      end
    end
  end
end
