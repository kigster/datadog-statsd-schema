# frozen_string_literal: true

require "spec_helper"

module Datadog
  class Statsd
    module Schema
      module Commands
        RSpec.describe Analyze do
          before do
            described_class.stdout = StringIO.new
            described_class.stderr = StringIO.new
          end

          describe "#call" do
            describe "command" do
              subject(:command) { described_class.new }

              it "requires file option" do
                expect { command.call }.to raise_error(SystemExit)
              end
            end

            it "analyzes a schema file and returns analysis results" do
              # Create a temporary schema file
              schema_content = <<~SCHEMA
                namespace :test do
                  tags do
                    tag :environment, values: %w[production staging]
                    tag :service, values: %w[api web]
                  end

                  metrics do
                    counter :requests_total do
                      description "Total requests"
                      tags required: [:environment], allowed: [:service]
                    end

                    gauge :memory_usage do
                      description "Memory usage"
                      tags allowed: [:environment]
                    end
                  end
                end
              SCHEMA

              # Write to temporary file
              require "tempfile"
              Tempfile.create(%w[test_schema .rb]) do |file|
                file.write(schema_content)
                file.flush

                command = described_class.new

                result = command.call(file: file.path)
                output = command.class.stdout.string

                expect(result).to be_a(Datadog::Statsd::Schema::AnalysisResult)
                expect(result.total_unique_metrics).to be > 0
                expect(result.total_possible_custom_metrics).to be > 0
                expect(result.metrics_analysis).to be_an(Array)
                expect(result.metrics_analysis.size).to eq(2) # requests_total and memory_usage

                expect(output).to include("Schema Analysis Results")
                expect(output).to include("Total unique metrics:")
                expect(output).to include("Total possible custom metric combinations:")
                expect(output).to include("test.requests_total")
                expect(output).to include("test.memory_usage")
              end
            end
          end
        end
      end
    end
  end
end
