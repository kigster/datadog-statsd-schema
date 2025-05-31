# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/module/delegation"
require "active_support/core_ext/string/inflections"

module Datadog
  class Statsd
    RSpec.describe Emitter do
      let(:mock_statsd) { instance_double(::Datadog::Statsd) }

      before do
        allow(described_class).to receive(:statsd).and_return(mock_statsd)
      end

      describe ".configure" do
        before do
          described_class.configure do |config|
            config.env = "test"
            config.version = "1.0.0"
          end
        end

        describe ".global_tags" do
          subject { described_class.global_tags }

          its(:env) { is_expected.to eq("test") }
          its(:version) { is_expected.to eq("1.0.0") }
        end
      end

      describe "#initialize" do
        context "when initialized with a string identifier" do
          subject(:emitter) { described_class.new("test") }

          it { is_expected.to be_a(described_class) }
          its(:tags) { is_expected.to include(emitter: "test") }
        end

        context "when initialized with a class identifier" do
          subject(:emitter) { described_class.new(String) }

          it { is_expected.to be_a(described_class) }
          its(:tags) { is_expected.to include(emitter: "string") }
        end

        context "when initialized with a module identifier" do
          subject(:emitter) { described_class.new(::Datadog::Statsd::Emitter) }

          it { is_expected.to be_a(described_class) }
          its(:tags) { is_expected.to include(emitter: "datadog.statsd.emitter") }
        end

        context "when initialized without arguments" do
          it "raises an ArgumentError" do
            expect { described_class.new }.to raise_error(ArgumentError, /use class methods/)
          end
        end
      end

      describe "#normalize_arguments" do
        context "when initialized with metric in constructor" do
          subject(:emitter) { described_class.new(nil, metric: "test.metric") }

          context "when calling increment with no arguments" do
            it "uses constructor metric" do
              expect(mock_statsd).to receive(:increment).with("test.metric")
              emitter.increment
            end
          end

          context "when calling increment with nil as first argument" do
            it "uses constructor metric" do
              expect(mock_statsd).to receive(:increment).with("test.metric")
              emitter.increment(nil)
            end
          end

          context "when calling increment with a provided metric" do
            it "uses provided metric" do
              expect(mock_statsd).to receive(:increment).with("other.metric")
              emitter.increment("other.metric")
            end
          end

          context "when calling gauge with nil and additional arguments" do
            it "preserves additional positional arguments" do
              expect(mock_statsd).to receive(:gauge).with("test.metric", 100)
              emitter.gauge(nil, 100)
            end
          end

          context "when calling increment with hash arguments" do
            it "supports optional hash arguments" do
              expect(mock_statsd).to receive(:increment).with("test.metric", by: 10)
              emitter.increment("test.metric", by: 10)
            end
          end
        end

        context "when initialized with tags in constructor" do
          subject(:emitter) { described_class.new(nil, tags: { env: "test", service: "api" }) }

          context "when calling increment with no additional tags" do
            it "includes constructor tags" do
              expect(mock_statsd).to receive(:increment).with("test.metric", tags: { env: "test", service: "api" })
              emitter.increment("test.metric")
            end
          end

          context "when calling increment with additional tags" do
            it "merges constructor tags with method tags" do
              expect(mock_statsd).to receive(:increment).with(
                "test.metric",
                tags: { env: "test", service: "api", user_id: 123 }
              )
              emitter.increment("test.metric", tags: { user_id: 123 })
            end
          end

          context "when method tags override constructor tags" do
            it "method tags take precedence" do
              expect(mock_statsd).to receive(:increment).with(
                "test.metric",
                tags: { env: "production", service: "api" }
              )
              emitter.increment("test.metric", tags: { env: "production" })
            end
          end
        end

        context "when initialized with ab_test in constructor" do
          subject(:emitter) { described_class.new(nil, ab_test: { "login_test_2025" => "control" }) }

          context "when calling increment" do
            it "converts ab_test to tags" do
              expect(mock_statsd).to receive(:increment).with(
                "test.metric",
                tags: { ab_test_name: "login_test_2025", ab_test_group: "control" }
              )
              emitter.increment("test.metric")
            end
          end

          context "when initialized with multiple ab_test entries" do
            subject(:emitter) do
              described_class.new(nil, ab_test: {
                                    "login_test_2025" => "control",
                                    "signup_test_2025" => "variant_a"
                                  })
            end

            it "uses last ab_test entry" do
              expect(mock_statsd).to receive(:increment).with(
                "test.metric",
                tags: { ab_test_name: "signup_test_2025", ab_test_group: "variant_a" }
              )
              emitter.increment("test.metric")
            end
          end
        end

        context "when ab_test provided in both constructor and method call" do
          subject(:emitter) { described_class.new(nil, ab_test: { "login_test_2025" => "control" }) }

          it "method ab_test overrides constructor ab_test" do
            expect(mock_statsd).to receive(:increment).with(
              "test.metric",
              tags: { ab_test_name: "signup_test", ab_test_group: "variant_a" }
            )
            emitter.increment("test.metric", ab_test: { "signup_test" => "variant_a" })
          end
        end

        context "when initialized with sample_rate in constructor" do
          subject(:emitter) { described_class.new(nil, sample_rate: 0.5) }

          context "when calling increment" do
            it "includes constructor sample_rate" do
              expect(mock_statsd).to receive(:increment).with("test.metric", sample_rate: 0.5)
              emitter.increment("test.metric")
            end
          end

          context "when method provides sample_rate" do
            it "method sample_rate overrides constructor sample_rate" do
              expect(mock_statsd).to receive(:increment).with("test.metric", sample_rate: 0.1)
              emitter.increment("test.metric", sample_rate: 0.1)
            end
          end

          context "when sample_rate is 1.0 (default)" do
            subject(:emitter) { described_class.new(nil, sample_rate: 1.0) }

            it "does not include sample_rate" do
              expect(mock_statsd).to receive(:increment).with("test.metric")
              emitter.increment("test.metric")
            end
          end
        end

        context "when initialized with identifier in constructor" do
          subject(:emitter) { described_class.new("TestController") }

          context "when calling increment" do
            it "includes identifier tag" do
              expect(mock_statsd).to receive(:increment).with(
                "test.metric",
                tags: { emitter: "test_controller" }
              )
              emitter.increment("test.metric")
            end
          end
        end

        context "when initialized with complex combination of options" do
          subject(:emitter) do
            described_class.new(
              "UserController",
              metric: "users.action",
              tags: { env: "test" },
              ab_test: { "login_test" => "control" },
              sample_rate: 0.8
            )
          end

          context "when calling increment with additional tags" do
            it "combines all constructor options correctly" do
              expect(mock_statsd).to receive(:increment).with(
                "users.action",
                tags: {
                  emitter: "user_controller",
                  env: "test",
                  ab_test_name: "login_test",
                  ab_test_group: "control",
                  user_id: 456
                },
                sample_rate: 0.8
              )
              emitter.increment(tags: { user_id: 456 })
            end
          end

          context "when method call overrides everything" do
            it "allows method call to override all options" do
              expect(mock_statsd).to receive(:gauge).with(
                "custom.metric",
                100,
                tags: {
                  emitter: "user_controller",
                  env: "production",
                  ab_test_name: "new_test",
                  ab_test_group: "variant_b",
                  user_id: 789
                },
                sample_rate: 0.1
              )
              emitter.gauge(
                "custom.metric",
                100,
                tags: { env: "production", user_id: 789 },
                ab_test: { "new_test" => "variant_b" },
                sample_rate: 0.1
              )
            end
          end
        end
      end

      describe "method forwarding" do
        subject(:emitter) { described_class.new("Email::SenderController") }

        let(:expected_tags) { { emitter: "email.sender_controller" } }

        describe "#increment" do
          it "forwards increment calls with correct arguments" do
            expect(mock_statsd).to receive(:increment).with(
              "test.counter",
              by: 2,
              tags: expected_tags
            )

            emitter.increment("test.counter", by: 2)
          end
        end

        describe "#gauge" do
          it "forwards gauge calls with correct arguments" do
            expect(mock_statsd).to receive(:gauge)
              .with("test.gauge", 100, tags: expected_tags)

            emitter.gauge("test.gauge", 100)
          end
        end

        describe "#histogram" do
          it "forwards histogram calls with correct arguments" do
            expect(mock_statsd).to receive(:histogram)
              .with("test.histogram", 0.5, tags: expected_tags)
            emitter.histogram("test.histogram", 0.5)
          end
        end

        describe "#distribution" do
          it "forwards distribution calls with correct arguments" do
            expect(mock_statsd).to receive(:distribution)
              .with("test.distribution", 0.3, tags: expected_tags)
            emitter.distribution("test.distribution", 0.3)
          end
        end
      end
    end
  end
end
