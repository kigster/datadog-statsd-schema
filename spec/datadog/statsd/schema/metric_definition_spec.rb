# frozen_string_literal: true

require "spec_helper"

module Datadog
  class Statsd
    module Schema
      RSpec.describe MetricDefinition do
        subject { described_class }

        describe ".new" do
          context "with required attributes only" do
            subject { described_class.new(name: :page_views, type: :counter) }

            its(:name) { is_expected.to eq(:page_views) }
            its(:type) { is_expected.to eq(:counter) }
            its(:description) { is_expected.to be_nil }
            its(:allowed_tags) { is_expected.to eq([]) }
            its(:required_tags) { is_expected.to eq([]) }
            its(:inherit_tags) { is_expected.to be_nil }
            its(:units) { is_expected.to be_nil }
          end

          context "with all optional attributes" do
            subject do
              described_class.new(
                name: :request_duration,
                type: :distribution,
                description: "HTTP request processing time",
                allowed_tags: %i[controller action method],
                required_tags: %i[controller],
                inherit_tags: "web.request.total",
                units: "milliseconds"
              )
            end

            its(:name) { is_expected.to eq(:request_duration) }
            its(:type) { is_expected.to eq(:distribution) }
            its(:description) { is_expected.to eq("HTTP request processing time") }
            its(:allowed_tags) { is_expected.to eq(%i[controller action method]) }
            its(:required_tags) { is_expected.to eq(%i[controller]) }
            its(:inherit_tags) { is_expected.to eq("web.request.total") }
            its(:units) { is_expected.to eq("milliseconds") }
          end

          context "with invalid metric type" do
            it "raises validation error" do
              expect do
                described_class.new(name: :invalid, type: :invalid_type)
              end.to raise_error(Dry::Struct::Error, /invalid_type.*failed/)
            end
          end

          context "with valid metric types" do
            let(:valid_types) { Datadog::Statsd::Schema::MetricDefinition::VALID_METRIC_TYPES }

            it "accepts all valid metric types" do
              valid_types.each do |type|
                expect do
                  described_class.new(name: :test_metric, type: type)
                end.not_to raise_error
              end
            end
          end
        end

        describe "#full_name" do
          subject { metric.full_name(namespace_path) }

          let(:metric) { described_class.new(name: :duration, type: :timing) }

          context "with no namespace path" do
            let(:namespace_path) { [] }

            it { is_expected.to eq("duration") }
          end

          context "when called without arguments" do
            subject { metric.full_name }

            it { is_expected.to eq("duration") }
          end

          context "with single namespace" do
            let(:namespace_path) { ["api"] }

            it { is_expected.to eq("api.duration") }
          end

          context "with multiple namespaces" do
            let(:namespace_path) { %w[web request] }

            it { is_expected.to eq("web.request.duration") }
          end
        end

        describe "#allows_tag?" do
          context "with no allowed tags restrictions" do
            subject { metric.allows_tag?(tag_name) }

            let(:metric) { described_class.new(name: :test, type: :counter) }

            context "with symbol tag" do
              let(:tag_name) { :any_tag }

              it { is_expected.to be true }
            end

            context "with string tag" do
              let(:tag_name) { "string_tag" }

              it { is_expected.to be true }
            end
          end

          context "with allowed tags restrictions" do
            subject { metric.allows_tag?(tag_name) }

            let(:metric) do
              described_class.new(
                name: :test,
                type: :counter,
                allowed_tags: %i[controller action method]
              )
            end

            context "with allowed symbol tag" do
              let(:tag_name) { :controller }

              it { is_expected.to be true }
            end

            context "with allowed string tag" do
              let(:tag_name) { "action" }

              it { is_expected.to be true }
            end

            context "with another allowed tag" do
              let(:tag_name) { :method }

              it { is_expected.to be true }
            end

            context "with non-allowed symbol tag" do
              let(:tag_name) { :status_code }

              it { is_expected.to be false }
            end

            context "with non-allowed string tag" do
              let(:tag_name) { "region" }

              it { is_expected.to be false }
            end
          end
        end

        describe "#requires_tag?" do
          subject { metric.requires_tag?(tag_name) }

          let(:metric) do
            described_class.new(name: :test, type: :counter, required_tags: %i[controller action])
          end

          context "with required symbol tag" do
            let(:tag_name) { :controller }

            it { is_expected.to be true }
          end

          context "with required string tag" do
            let(:tag_name) { "action" }

            it { is_expected.to be true }
          end

          context "with non-required symbol tag" do
            let(:tag_name) { :method }

            it { is_expected.to be false }
          end

          context "with non-required string tag" do
            let(:tag_name) { "region" }

            it { is_expected.to be false }
          end
        end

        describe "#missing_required_tags" do
          subject { metric.missing_required_tags(provided_tags) }

          let(:metric) do
            described_class.new(
              name: :test,
              type: :counter,
              required_tags: %i[controller action method]
            )
          end

          context "when all required tags provided" do
            let(:provided_tags) { { controller: "home", action: "index", method: "get" } }

            it { is_expected.to eq([]) }
          end

          context "when some required tags missing" do
            let(:provided_tags) { { controller: "home" } }

            it { is_expected.to match_array(%i[action method]) }
          end

          context "with string keys" do
            let(:provided_tags) { { "controller" => "home", "action" => "index" } }

            it { is_expected.to eq([:method]) }
          end

          context "when no tags provided" do
            let(:provided_tags) { {} }

            it { is_expected.to match_array(%i[controller action method]) }
          end
        end

        describe "#invalid_tags" do
          subject { metric.invalid_tags(provided_tags) }

          context "with no tag restrictions" do
            let(:metric) { described_class.new(name: :test, type: :counter) }
            let(:provided_tags) { { any_tag: "value", another: "value" } }

            it { is_expected.to eq([]) }
          end

          context "with allowed tags restrictions" do
            let(:metric) do
              described_class.new(name: :test, type: :counter, allowed_tags: %i[controller action])
            end

            context "with valid tags only" do
              let(:provided_tags) { { controller: "home", action: "index" } }

              it { is_expected.to eq([]) }
            end

            context "with some invalid tags" do
              let(:provided_tags) { { controller: "home", action: "index", method: "get", region: "us" } }

              it { is_expected.to match_array(%i[method region]) }
            end

            context "with string keys" do
              let(:provided_tags) { { "controller" => "home", "invalid_tag" => "value" } }

              it { is_expected.to eq([:invalid_tag]) }
            end
          end
        end

        describe "#valid_tags?" do
          subject { metric.valid_tags?(provided_tags) }

          let(:metric) do
            described_class.new(
              name: :test,
              type: :counter,
              allowed_tags: %i[controller action method],
              required_tags: %i[controller]
            )
          end

          context "with valid tag set" do
            let(:provided_tags) { { controller: "home", action: "index" } }

            it { is_expected.to be true }
          end

          context "when required tags missing" do
            let(:provided_tags) { { action: "index" } }

            it { is_expected.to be false }
          end

          context "when invalid tags present" do
            let(:provided_tags) { { controller: "home", invalid_tag: "value" } }

            it { is_expected.to be false }
          end

          context "with both missing required and invalid tags" do
            let(:provided_tags) { { invalid_tag: "value" } }

            it { is_expected.to be false }
          end
        end

        describe "metric type predicates" do
          describe "#timing_metric?" do
            subject { metric.timing_metric? }

            context "with timing-based metrics" do
              %i[timing distribution histogram].each do |type|
                context "with #{type} type" do
                  let(:metric) { described_class.new(name: :test, type: type) }

                  it { is_expected.to be true }
                end
              end
            end

            context "with non-timing metrics" do
              %i[counter gauge set].each do |type|
                context "with #{type} type" do
                  let(:metric) { described_class.new(name: :test, type: type) }

                  it { is_expected.to be false }
                end
              end
            end
          end

          describe "#counting_metric?" do
            subject { metric.counting_metric? }

            context "with counter type" do
              let(:metric) { described_class.new(name: :test, type: :counter) }

              it { is_expected.to be true }
            end

            context "with non-counter metrics" do
              %i[gauge timing distribution histogram set].each do |type|
                context "with #{type} type" do
                  let(:metric) { described_class.new(name: :test, type: type) }

                  it { is_expected.to be false }
                end
              end
            end
          end

          describe "#gauge_metric?" do
            subject { metric.gauge_metric? }

            context "with gauge type" do
              let(:metric) { described_class.new(name: :test, type: :gauge) }

              it { is_expected.to be true }
            end

            context "with non-gauge metrics" do
              %i[counter timing distribution histogram set].each do |type|
                context "with #{type} type" do
                  let(:metric) { described_class.new(name: :test, type: type) }

                  it { is_expected.to be false }
                end
              end
            end
          end

          describe "#set_metric?" do
            subject { metric.set_metric? }

            context "with set type" do
              let(:metric) { described_class.new(name: :test, type: :set) }

              it { is_expected.to be true }
            end

            context "with non-set metrics" do
              %i[counter gauge timing distribution histogram].each do |type|
                context "with #{type} type" do
                  let(:metric) { described_class.new(name: :test, type: type) }

                  it { is_expected.to be false }
                end
              end
            end
          end
        end

        describe "tag inheritance" do
          let(:parent_metric) do
            described_class.new(
              name: :parent,
              type: :counter,
              allowed_tags: %i[controller action],
              required_tags: %i[controller]
            )
          end

          let(:child_metric) do
            described_class.new(
              name: :child,
              type: :counter,
              allowed_tags: %i[method status_code],
              required_tags: %i[method],
              inherit_tags: "web.parent"
            )
          end

          let(:schema_registry) do
            double("schema_registry").tap do |registry|
              allow(registry).to receive(:find_metric).with("web.parent").and_return(parent_metric)
            end
          end

          describe "#effective_allowed_tags" do
            subject { metric.effective_allowed_tags(schema_registry) }

            context "with parent metric having no inheritance" do
              let(:metric) { parent_metric }

              it { is_expected.to eq(%i[controller action]) }
            end

            context "with child metric and no schema registry" do
              subject { child_metric.effective_allowed_tags }

              it { is_expected.to eq(%i[method status_code]) }
            end

            context "with child metric and schema registry" do
              let(:metric) { child_metric }

              it { is_expected.to match_array(%i[controller action method status_code]) }
            end

            context "when inherited metric not found" do
              let(:metric) { child_metric }

              before do
                allow(schema_registry).to receive(:find_metric).and_return(nil)
              end

              it { is_expected.to eq(%i[method status_code]) }
            end
          end

          describe "#effective_required_tags" do
            subject { metric.effective_required_tags(schema_registry) }

            context "with parent metric having no inheritance" do
              let(:metric) { parent_metric }

              it { is_expected.to eq(%i[controller]) }
            end

            context "with child metric and no schema registry" do
              subject { child_metric.effective_required_tags }

              it { is_expected.to eq(%i[method]) }
            end

            context "with child metric and schema registry" do
              let(:metric) { child_metric }

              it { is_expected.to match_array(%i[controller method]) }
            end

            context "when inherited metric not found" do
              let(:metric) { child_metric }

              before do
                allow(schema_registry).to receive(:find_metric).and_return(nil)
              end

              it { is_expected.to eq(%i[method]) }
            end
          end
        end
      end
    end
  end
end
