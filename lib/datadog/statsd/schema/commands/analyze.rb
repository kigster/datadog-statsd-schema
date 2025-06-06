# frozen_string_literal: true

require "dry/cli"

module Datadog
  class Statsd
    module Schema
      module Commands
        class Analyze < Dry::CLI::Command
          class << self
            attr_accessor :stdout, :stderr
          end

          self.stdout = $stdout
          self.stderr = $stderr

          desc "Analyze a schema file for metrics and validation"

          option :file, aliases: %w[-f], type: :string, required: true, desc: "Path to the schema file to analyze"

          def call(**options)
            file = options[:file]

            unless file
              self.class.stderr.puts "Error: --file option is required"
              self.class.stderr.puts "Usage: dss analyze --file <schema.rb>"
              exit 1
            end

            # TODO: Implement schema analysis functionality
            self.class.stderr.puts "Analyzing schema file: #{file}"
            schema = ::Datadog::Statsd::Schema.load_file(file)
            ::Datadog::Statsd::Schema::Analyzer.new([schema], stdout: self.class.stdout, stderr: self.class.stderr).analyze
          end
        end
      end
    end
  end
end
