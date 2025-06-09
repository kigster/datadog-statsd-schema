# frozen_string_literal: true

require "dry/cli"

module Datadog
  class Statsd
    module Schema
      module Commands
        # @description Analyze a schema file for metrics and validation
        class Analyze < Dry::CLI::Command
          class << self
            attr_accessor :stdout, :stderr
          end

          self.stdout = $stdout
          self.stderr = $stderr

          desc "Analyze a schema file for metrics and validation"

          option :file, aliases: %w[-f], type: :string, required: true, desc: "Path to the schema file to analyze"
          option :color, aliases: %w[-c], type: :boolean, required: false, desc: "Enable/Disable color output", default: true
          option :format, aliases: %w[-o], type: :string, required: false, desc: "Output format, supports: json, yaml, text", default: :text

          # @description Analyze a schema file for metrics and validation
          # @param options [Hash] The options for the command
          # @option options [String] :file The path to the schema file to analyze
          # @option options [Boolean] :color Enable/Disable color output
          # @return [void]
          def call(**options)
            file = options[:file]

            unless file
              warn "Error: --file option is required"
              warn "Usage: dss analyze --file <schema.rb>"
              exit 1
            end

            warn "Analyzing Schema File:"
            warn " • file   #{file.green}"
            warn " • color: #{(options[:color] ? "enabled" : "disabled").yellow}"
            warn " • formar #{options[:format].to_s.red}"
            @schema = ::Datadog::Statsd::Schema.load_file(file)
            ::Datadog::Statsd::Schema::Analyzer.new([@schema],
                                                    format: (options[:format] || :text).to_sym,
                                                    stdout: self.class.stdout,
                                                    stderr: self.class.stderr,
                                                    color: options[:color]).tap do |analyzer|
                                                      puts analyzer.render
                                                    end.analyze
          end

          def warn(...)
            self.class.stderr.puts(...)
          end

          def puts(...)
            self.class.stdout.puts(...)
          end
        end
      end
    end
  end
end
