# frozen_string_literal: true

module Datadog
  class Statsd
    module Schema
      module Commands
        # CLI commands will be defined here
      end
    end
  end
end

# Require all command files
require_relative "commands/analyze"
