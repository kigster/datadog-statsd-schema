# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/module/delegation"
require "active_support/core_ext/string/inflections"

module Datadog
  class Statsd
    RSpec.describe Emitter, "with schema validation" do
      let(:mock_statsd) { instance_double(::Datadog::Statsd) }
      let(:sample_schema) { build_sample_schema }

      before do
        allow(described_class).to receive(:statsd).and_return(mock_statsd)
      end

      def build_sample_schema
        ::Datadog.schema do
          namespace :web do
            tags do
              tag :controller, values: %w[users posts home]
              tag :action, values: %w[index show create update destroy]
              tag :method, values: %i[get post put delete], type: :symbol
              tag :status_code, type: :integer, validate: ->(code) { (100..599).include?(code.to_i) }
              tag :env, values: %w[development staging production]
            end

            metrics do
              counter :page_views,
                      description: "Number of page views",
                      tags: {
                        allowed: %w[controller action method env],
                        required: %w[controller]
                      }

              distribution :request_duration,
                           description: "Request processing time",
                           tags: {
                             allowed: %w[controller action method status_code],
                             required: %w[controller action]
                           }

              gauge :active_users,
                    description: "Current active users",
                    tags: { allowed: %w[env] }
            end
          end
        end
      end

      describe "#initialize" do
        context "when initialized with schema" do
          subject(:emitter) { described_class.new("TestController", schema: sample_schema) }

          its(:schema) { is_expected.to eq(sample_schema) }
          its(:validation_mode) { is_expected.to eq(:strict) }
        end

        context "when initialized with schema and custom validation mode" do
          subject(:emitter) do
            described_class.new("TestController", schema: sample_schema, validation_mode: :warn)
          end

          its(:validation_mode) { is_expected.to eq(:warn) }
        end
      end

      describe "schema validation" do
        subject(:emitter) { described_class.new("TestController", schema: sample_schema) }

        context "when metric exists in schema" do
          context "with valid metric type and tags" do
            it "allows the metric call" do
              expect(mock_statsd).to receive(:increment).with(
                "web.page_views",
                tags: hash_including(controller: "users", emitter: "test_controller")
              )

              emitter.increment("web.page_views", tags: { controller: "users" })
            end
          end

          context "with valid metric type and all required tags" do
            it "allows the metric call with multiple tags" do
              expect(mock_statsd).to receive(:distribution).with(
                "web.request_duration",
                100,
                tags: hash_including(controller: "users", action: "show", method: "get", emitter: "test_controller")
              )

              emitter.distribution(
                "web.request_duration",
                100,
                tags: { controller: "users", action: "show", method: "get" }
              )
            end
          end
        end

        context "when metric does not exist in schema" do
          it "raises UnknownMetricError for non-existent metric" do
            expect do
              emitter.increment("unknown.metric")
            end.to raise_error(ArgumentError, /Unknown metric 'unknown.metric'/)
          end

          it "provides suggestions for similar metric names" do
            expect do
              emitter.increment("web.page_view") # missing 's'
            end.to raise_error(ArgumentError, /Did you mean: web\.page_views/)
          end

          it "lists available metrics when no suggestions found" do
            expect do
              emitter.increment("completely.different")
            end.to raise_error(ArgumentError, /Available metrics:.*web\.page_views/)
          end
        end

        context "when metric type does not match schema" do
          it "raises InvalidMetricTypeError" do
            expect do
              emitter.gauge("web.page_views") # should be counter
            end.to raise_error(ArgumentError, /Invalid metric type.*Expected 'counter', got 'gauge'/)
          end
        end

        context "when required tags are missing" do
          it "raises MissingRequiredTagError" do
            expect do
              emitter.increment("web.page_views") # missing required 'controller' tag
            end.to raise_error(ArgumentError, /Missing required tags.*controller/)
          end

          it "allows metric when all required tags are present" do
            expect(mock_statsd).to receive(:increment).with(
              "web.page_views",
              tags: hash_including(controller: "users", emitter: "test_controller")
            )

            emitter.increment("web.page_views", tags: { controller: "users" })
          end
        end

        context "when invalid tags are provided" do
          it "raises InvalidTagError for disallowed tags" do
            expect do
              emitter.increment(
                "web.page_views",
                tags: { controller: "users", invalid_tag: "value" }
              )
            end.to raise_error(ArgumentError, /Invalid tags.*invalid_tag/)
          end
        end

        context "when tag values are invalid" do
          context "with enum validation" do
            it "raises error for invalid enum value" do
              expect do
                emitter.increment(
                  "web.page_views",
                  tags: { controller: "invalid_controller" }
                )
              end.to raise_error(ArgumentError,
                                 /Invalid value 'invalid_controller'.*Allowed values: users, posts, home/)
            end
          end

          context "with type validation" do
            it "raises error for invalid integer type" do
              expect do
                emitter.distribution(
                  "web.request_duration",
                  100,
                  tags: { controller: "users", action: "show", status_code: "not_a_number" }
                )
              end.to raise_error(ArgumentError, /Tag 'status_code'.*must be an integer/)
            end

            it "allows string representation of integers" do
              expect(mock_statsd).to receive(:distribution).with(
                "web.request_duration",
                100,
                tags: hash_including(controller: "users", action: "show", status_code: "200",
                                     emitter: "test_controller")
              )

              emitter.distribution(
                "web.request_duration",
                100,
                tags: { controller: "users", action: "show", status_code: "200" }
              )
            end
          end

          context "with custom validation" do
            it "raises error when custom validation fails" do
              expect do
                emitter.distribution(
                  "web.request_duration",
                  100,
                  tags: { controller: "users", action: "show", status_code: 999 }
                )
              end.to raise_error(ArgumentError, /Custom validation failed/)
            end
          end
        end
      end

      describe "validation modes" do
        context "when validation_mode is :strict (default)" do
          subject(:emitter) { described_class.new("TestController", schema: sample_schema) }

          it "raises error for invalid metrics" do
            expect do
              emitter.increment("unknown.metric")
            end.to raise_error(ArgumentError)
          end
        end

        context "when validation_mode is :warn" do
          subject(:emitter) do
            described_class.new("TestController", schema: sample_schema, validation_mode: :warn)
          end

          it "warns but does not raise error for invalid metrics" do
            expect do
              expect do
                expect(mock_statsd).to receive(:increment).with(
                  "unknown.metric",
                  tags: { emitter: "test_controller" }
                )
                emitter.increment("unknown.metric")
              end.to output(/Schema validation warning/).to_stderr
            end.not_to raise_error
          end

          it "still sends the metric to statsd" do
            expect(mock_statsd).to receive(:increment).with(
              "unknown.metric",
              tags: { emitter: "test_controller" }
            )

            emitter.increment("unknown.metric")
          end
        end

        context "when validation_mode is :drop" do
          subject(:emitter) do
            described_class.new("TestController", schema: sample_schema, validation_mode: :drop)
          end

          it "silently drops invalid metrics without error or warning" do
            expect(mock_statsd).not_to receive(:increment)

            expect do
              emitter.increment("unknown.metric")
            end.not_to raise_error
          end

          it "still sends valid metrics" do
            expect(mock_statsd).to receive(:increment).with(
              "web.page_views",
              tags: hash_including(controller: "users", emitter: "test_controller")
            )

            emitter.increment("web.page_views", tags: { controller: "users" })
          end
        end

        context "when validation_mode is :off" do
          subject(:emitter) do
            described_class.new("TestController", schema: sample_schema, validation_mode: :off)
          end

          it "performs no validation and sends all metrics" do
            expect(mock_statsd).to receive(:increment).with(
              "unknown.metric",
              tags: { emitter: "test_controller" }
            )

            emitter.increment("unknown.metric")
          end
        end
      end

      describe "interaction with existing functionality" do
        subject(:emitter) do
          described_class.new(
            "TestController",
            metric: "web.page_views",
            tags: { env: "production" },
            schema: sample_schema
          )
        end

        context "when using constructor defaults with schema validation" do
          it "validates constructor metric and tags" do
            expect(mock_statsd).to receive(:increment).with(
              "web.page_views",
              tags: hash_including(controller: "users", env: "production", emitter: "test_controller")
            )

            emitter.increment(tags: { controller: "users" })
          end

          it "raises error when constructor metric is invalid" do
            invalid_emitter = described_class.new(
              "TestController",
              metric: "web.invalid_metric",
              schema: sample_schema
            )

            expect do
              invalid_emitter.increment
            end.to raise_error(ArgumentError, /Unknown metric/)
          end
        end

        context "when using ab_test with schema validation" do
          subject(:emitter) do
            described_class.new(
              "TestController",
              ab_test: { "test_2025" => "control" },
              schema: sample_schema
            )
          end

          it "validates metrics with ab_test tags included" do
            expect(mock_statsd).to receive(:increment).with(
              "web.page_views",
              tags: hash_including(
                controller: "users",
                ab_test_name: "test_2025",
                ab_test_group: "control",
                emitter: "test_controller"
              )
            )

            emitter.increment("web.page_views", tags: { controller: "users" })
          end
        end
      end

      describe "metric type normalization" do
        subject(:emitter) { described_class.new("TestController", schema: sample_schema) }

        it "normalizes increment to counter" do
          expect(mock_statsd).to receive(:increment).with(
            "web.page_views",
            tags: hash_including(controller: "users", emitter: "test_controller")
          )
          emitter.increment("web.page_views", tags: { controller: "users" })
        end

        it "normalizes decrement to counter" do
          expect(mock_statsd).to receive(:decrement).with(
            "web.page_views",
            tags: hash_including(controller: "users", emitter: "test_controller")
          )
          emitter.decrement("web.page_views", tags: { controller: "users" })
        end

        it "validates gauge metrics correctly" do
          expect(mock_statsd).to receive(:gauge).with(
            "web.active_users",
            100,
            tags: hash_including(env: "production", emitter: "test_controller")
          )
          emitter.gauge("web.active_users", 100, tags: { env: "production" })
        end

        it "validates distribution metrics correctly" do
          expect(mock_statsd).to receive(:distribution).with(
            "web.request_duration",
            100,
            tags: hash_including(controller: "users", action: "show", emitter: "test_controller")
          )
          emitter.distribution(
            "web.request_duration",
            100,
            tags: { controller: "users", action: "show" }
          )
        end
      end

      describe "error message quality" do
        subject(:emitter) { described_class.new("TestController", schema: sample_schema) }

        it "provides clear error for missing required tags" do
          expect do
            emitter.distribution("web.request_duration", 100, tags: { controller: "users" })
          end.to raise_error(ArgumentError, /Missing required tags.*action.*Required tags: controller, action/)
        end

        it "provides clear error for invalid tag values" do
          expect do
            emitter.increment("web.page_views", tags: { controller: "invalid" })
          end.to raise_error(ArgumentError, /Invalid value 'invalid'.*Allowed values: users, posts, home/)
        end

        it "provides clear error for type mismatches" do
          expect do
            emitter.gauge("web.page_views")
          end.to raise_error(ArgumentError, /Invalid metric type.*Expected 'counter', got 'gauge'/)
        end
      end

      describe "no schema provided" do
        subject(:emitter) { described_class.new("TestController") }

        it "performs no validation when no schema is provided" do
          expect(mock_statsd).to receive(:increment).with(
            "any.metric",
            tags: { emitter: "test_controller" }
          )
          emitter.increment("any.metric")
        end
      end
    end
  end
end
