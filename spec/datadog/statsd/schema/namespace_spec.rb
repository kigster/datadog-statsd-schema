# frozen_string_literal: true

require "spec_helper"

module Datadog
  class Statsd
    module Schema
      RSpec.describe Namespace do
        subject { described_class }

        let(:tag_def1) do
          Datadog::Statsd::Schema::TagDefinition.new(
            name: :controller,
            values: %w[home users posts]
          )
        end

        let(:tag_def2) do
          Datadog::Statsd::Schema::TagDefinition.new(
            name: :action,
            values: %w[index show create update]
          )
        end

        let(:metric_def1) do
          Datadog::Statsd::Schema::MetricDefinition.new(
            name: :page_views,
            type: :counter,
            allowed_tags: %i[controller action],
            required_tags: %i[controller]
          )
        end

        let(:metric_def2) do
          Datadog::Statsd::Schema::MetricDefinition.new(
            name: :request_duration,
            type: :distribution,
            description: "Request processing time",
            allowed_tags: %i[controller action],
            required_tags: %i[controller]
          )
        end

        describe ".new" do
          subject { described_class.new(name: :web) }

          context "with required name only" do
            its(:name) { is_expected.to eq(:web) }
            its(:tags) { is_expected.to eq({}) }
            its(:metrics) { is_expected.to eq({}) }
            its(:namespaces) { is_expected.to eq({}) }
            its(:description) { is_expected.to be_nil }
          end

          context "with all optional attributes" do
            subject do
              described_class.new(
                name: :api,
                description: "API metrics namespace",
                tags: {
                  controller: tag_def1
                },
                metrics: {
                  page_views: metric_def1
                },
                namespaces: {}
              )
            end

            its(:name) { is_expected.to eq(:api) }
            its(:description) { is_expected.to eq("API metrics namespace") }
            its(:tags) { is_expected.to eq({ controller: tag_def1 }) }
            its(:metrics) { is_expected.to eq({ page_views: metric_def1 }) }
          end
        end

        describe "#full_path" do
          subject { namespace.full_path(parent_path) }

          let(:namespace) { described_class.new(name: :request) }

          context "when no parent path provided" do
            let(:parent_path) { [] }

            it { is_expected.to eq([:request]) }
          end

          context "when parent path provided" do
            let(:parent_path) { %i[web api] }

            it { is_expected.to eq(%i[web api request]) }
          end

          context "when called without arguments" do
            subject { namespace.full_path }

            it { is_expected.to eq([:request]) }
          end
        end

        describe "finding elements" do
          subject { namespace }

          let(:namespace) do
            described_class.new(
              name: :web,
              tags: {
                controller: tag_def1,
                action: tag_def2
              },
              metrics: {
                page_views: metric_def1,
                request_duration: metric_def2
              }
            )
          end

          describe "#find_metric" do
            context "with existing metrics" do
              it "finds by symbol" do
                expect(subject.find_metric(:page_views)).to eq(metric_def1)
              end

              it "finds by string" do
                expect(subject.find_metric("page_views")).to eq(metric_def1)
              end

              it "finds second metric by symbol" do
                expect(subject.find_metric(:request_duration)).to eq(metric_def2)
              end
            end

            context "with non-existent metric" do
              it "returns nil" do
                expect(subject.find_metric(:nonexistent)).to be_nil
              end
            end
          end

          describe "#find_tag" do
            context "with existing tags" do
              it "finds by symbol" do
                expect(subject.find_tag(:controller)).to eq(tag_def1)
              end

              it "finds by string" do
                expect(subject.find_tag("controller")).to eq(tag_def1)
              end

              it "finds second tag by symbol" do
                expect(subject.find_tag(:action)).to eq(tag_def2)
              end
            end

            context "with non-existent tag" do
              it "returns nil" do
                expect(subject.find_tag(:nonexistent)).to be_nil
              end
            end
          end

          describe "#find_namespace" do
            subject { namespace_with_nested }

            let(:nested_namespace) { described_class.new(name: :api) }
            let(:namespace_with_nested) do
              described_class.new(name: :web, namespaces: { api: nested_namespace })
            end

            context "with existing nested namespace" do
              it "finds by symbol" do
                expect(subject.find_namespace(:api)).to eq(nested_namespace)
              end

              it "finds by string" do
                expect(subject.find_namespace("api")).to eq(nested_namespace)
              end
            end

            context "with non-existent namespace" do
              it "returns nil" do
                expect(subject.find_namespace(:nonexistent)).to be_nil
              end
            end
          end
        end

        describe "adding elements" do
          subject { namespace }

          let(:namespace) { described_class.new(name: :web) }

          describe "#add_metric" do
            subject { namespace.add_metric(metric_def1) }

            it "returns new namespace instance" do
              expect(subject).not_to eq(namespace)
            end

            its(:metrics) { is_expected.to eq({ page_views: metric_def1 }) }

            it "leaves original namespace unchanged" do
              subject
              expect(namespace.metrics).to eq({})
            end
          end

          describe "#add_tag" do
            subject { namespace.add_tag(tag_def1) }

            it "returns new namespace instance" do
              expect(subject).not_to eq(namespace)
            end

            its(:tags) { is_expected.to eq({ controller: tag_def1 }) }

            it "leaves original namespace unchanged" do
              subject
              expect(namespace.tags).to eq({})
            end
          end

          describe "#add_namespace" do
            subject { namespace.add_namespace(nested_namespace) }

            let(:nested_namespace) { described_class.new(name: :api) }

            it "returns new namespace instance" do
              expect(subject).not_to eq(namespace)
            end

            its(:namespaces) { is_expected.to eq({ api: nested_namespace }) }

            it "leaves original namespace unchanged" do
              subject
              expect(namespace.namespaces).to eq({})
            end
          end
        end

        describe "listing elements" do
          subject { namespace }

          let(:namespace) do
            described_class.new(
              name: :web,
              tags: {
                controller: tag_def1,
                action: tag_def2
              },
              metrics: {
                page_views: metric_def1,
                request_duration: metric_def2
              },
              namespaces: {
                api: described_class.new(name: :api)
              }
            )
          end

          describe "#metric_names" do
            subject { namespace.metric_names }

            it { is_expected.to match_array(%i[page_views request_duration]) }
          end

          describe "#tag_names" do
            subject { namespace.tag_names }

            it { is_expected.to match_array(%i[controller action]) }
          end

          describe "#namespace_names" do
            subject { namespace.namespace_names }

            it { is_expected.to eq([:api]) }
          end
        end

        describe "checking existence" do
          subject { namespace }

          let(:namespace) do
            described_class.new(
              name: :web,
              tags: {
                controller: tag_def1
              },
              metrics: {
                page_views: metric_def1
              },
              namespaces: {
                api: described_class.new(name: :api)
              }
            )
          end

          describe "#has_metric?" do
            context "with existing metric" do
              it "returns true for symbol" do
                expect(subject.has_metric?(:page_views)).to be true
              end

              it "returns true for string" do
                expect(subject.has_metric?("page_views")).to be true
              end
            end

            context "with non-existing metric" do
              it "returns false" do
                expect(subject.has_metric?(:nonexistent)).to be false
              end
            end
          end

          describe "#has_tag?" do
            context "with existing tag" do
              it "returns true for symbol" do
                expect(subject.has_tag?(:controller)).to be true
              end

              it "returns true for string" do
                expect(subject.has_tag?("controller")).to be true
              end
            end

            context "with non-existing tag" do
              it "returns false" do
                expect(subject.has_tag?(:nonexistent)).to be false
              end
            end
          end

          describe "#has_namespace?" do
            context "with existing namespace" do
              it "returns true for symbol" do
                expect(subject.has_namespace?(:api)).to be true
              end

              it "returns true for string" do
                expect(subject.has_namespace?("api")).to be true
              end
            end

            context "with non-existing namespace" do
              it "returns false" do
                expect(subject.has_namespace?(:nonexistent)).to be false
              end
            end
          end
        end

        describe "#all_metrics" do
          subject { web_namespace.all_metrics(parent_path) }

          let(:api_metric) do
            Datadog::Statsd::Schema::MetricDefinition.new(name: :requests, type: :counter)
          end

          let(:api_namespace) { described_class.new(name: :api, metrics: { requests: api_metric }) }

          let(:web_namespace) do
            described_class.new(
              name: :web,
              metrics: {
                page_views: metric_def1
              },
              namespaces: {
                api: api_namespace
              }
            )
          end

          context "with default parent path" do
            let(:parent_path) { [] }

            its(:keys) { is_expected.to contain_exactly("web.page_views", "web.api.requests") }

            describe "web.page_views metric info" do
              subject { web_namespace.all_metrics(parent_path)["web.page_views"] }

              its([:definition]) { is_expected.to eq(metric_def1) }
              its([:namespace_path]) { is_expected.to eq([:web]) }
              its([:namespace]) { is_expected.to eq(web_namespace) }
            end

            describe "web.api.requests metric info" do
              subject { web_namespace.all_metrics(parent_path)["web.api.requests"] }

              its([:definition]) { is_expected.to eq(api_metric) }
              its([:namespace_path]) { is_expected.to eq(%i[web api]) }
              its([:namespace]) { is_expected.to eq(api_namespace) }
            end
          end

          context "with custom parent path" do
            subject { api_namespace.all_metrics(%i[root web]) }

            its(:keys) { is_expected.to eq(["root.web.api.requests"]) }

            describe "metric namespace path" do
              subject { api_namespace.all_metrics(%i[root web])["root.web.api.requests"] }

              its([:namespace_path]) { is_expected.to eq(%i[root web api]) }
            end
          end
        end

        describe "#effective_tags" do
          subject { namespace.effective_tags(parent_tags) }

          let(:namespace) do
            described_class.new(name: :web, tags: { controller: tag_def1, action: tag_def2 })
          end

          context "with no parent tags" do
            let(:parent_tags) { {} }

            it { is_expected.to eq({ controller: tag_def1, action: tag_def2 }) }
          end

          context "with parent tags" do
            let(:parent_tag) do
              Datadog::Statsd::Schema::TagDefinition.new(name: :region, values: %w[us eu])
            end
            let(:parent_tags) { { region: parent_tag } }

            it { is_expected.to eq({ region: parent_tag, controller: tag_def1, action: tag_def2 }) }
          end

          context "with conflicting parent tags" do
            let(:parent_tag) do
              Datadog::Statsd::Schema::TagDefinition.new(
                name: :controller,
                values: %w[different values]
              )
            end
            let(:parent_tags) { { controller: parent_tag } }

            it "prioritizes own tags over parent tags" do
              expect(subject[:controller]).to eq(tag_def1)
            end
          end
        end

        describe "#validate_tag_references" do
          subject { namespace.validate_tag_references }

          let(:invalid_metric) do
            Datadog::Statsd::Schema::MetricDefinition.new(
              name: :invalid_metric,
              type: :counter,
              allowed_tags: %i[controller nonexistent_tag],
              required_tags: %i[another_missing_tag]
            )
          end

          let(:valid_metric) do
            Datadog::Statsd::Schema::MetricDefinition.new(
              name: :valid_metric,
              type: :counter,
              allowed_tags: %i[controller],
              required_tags: %i[action]
            )
          end

          context "with invalid tag references" do
            let(:namespace) do
              described_class.new(
                name: :web,
                tags: {
                  controller: tag_def1,
                  action: tag_def2
                },
                metrics: {
                  invalid_metric: invalid_metric
                }
              )
            end

            it "includes error for unknown allowed tag" do
              expect(subject).to include(
                "Metric invalid_metric references unknown tag: nonexistent_tag"
              )
            end

            it "includes error for unknown required tag" do
              expect(subject).to include(
                "Metric invalid_metric requires unknown tag: another_missing_tag"
              )
            end
          end

          context "with mixed valid and invalid metrics" do
            let(:namespace) do
              described_class.new(
                name: :web,
                tags: {
                  controller: tag_def1,
                  action: tag_def2
                },
                metrics: {
                  invalid_metric: invalid_metric,
                  valid_metric: valid_metric
                }
              )
            end

            it "includes error for invalid metric allowed tag" do
              expect(subject).to include(
                "Metric invalid_metric references unknown tag: nonexistent_tag"
              )
            end

            it "includes error for invalid metric required tag" do
              expect(subject).to include(
                "Metric invalid_metric requires unknown tag: another_missing_tag"
              )
            end

            it "does not include errors for valid metric" do
              valid_metric_errors = subject.select { |error| error.include?("Metric valid_metric") }
              expect(valid_metric_errors).to be_empty
            end
          end

          context "with nested namespace validation" do
            let(:nested_namespace) do
              described_class.new(name: :api, metrics: { invalid_nested: invalid_metric })
            end

            let(:namespace) do
              described_class.new(
                name: :web,
                tags: {
                  controller: tag_def1,
                  action: tag_def2
                },
                metrics: {
                  valid_metric: valid_metric
                }
              ).add_namespace(nested_namespace)
            end

            it "includes errors from nested namespaces" do
              expect(subject).to include(
                "Metric invalid_nested references unknown tag: nonexistent_tag"
              )
            end
          end

          context "with all valid references" do
            let(:namespace) do
              described_class.new(
                name: :web,
                tags: {
                  controller: tag_def1,
                  action: tag_def2
                },
                metrics: {
                  valid_metric: valid_metric
                }
              )
            end

            it { is_expected.to eq([]) }
          end
        end

        describe "path-based finding" do
          let(:nested_metric) do
            Datadog::Statsd::Schema::MetricDefinition.new(name: :duration, type: :timing)
          end

          let(:deeply_nested_namespace) do
            described_class.new(name: :timing, metrics: { duration: nested_metric })
          end

          let(:api_namespace) do
            described_class.new(name: :api, namespaces: { timing: deeply_nested_namespace })
          end

          let(:web_namespace) do
            described_class.new(
              name: :web,
              metrics: {
                page_views: metric_def1
              },
              namespaces: {
                api: api_namespace
              }
            )
          end

          describe "#find_metric_by_path" do
            subject { web_namespace.find_metric_by_path(path) }

            context "with metric in current namespace" do
              let(:path) { "page_views" }

              it { is_expected.to eq(metric_def1) }
            end

            context "with metric in nested namespace" do
              let(:path) { "api.timing.duration" }

              it { is_expected.to eq(nested_metric) }
            end

            context "with non-existent path" do
              let(:path) { "nonexistent.path" }

              it { is_expected.to be_nil }
            end

            context "with partially valid path" do
              let(:path) { "api.nonexistent" }

              it { is_expected.to be_nil }
            end
          end

          describe "#find_namespace_by_path" do
            subject { web_namespace.find_namespace_by_path(path) }

            context "with empty path" do
              let(:path) { "" }

              it { is_expected.to eq(web_namespace) }
            end

            context "with direct nested namespace" do
              let(:path) { "api" }

              it { is_expected.to eq(api_namespace) }
            end

            context "with deeply nested namespace" do
              let(:path) { "api.timing" }

              it { is_expected.to eq(deeply_nested_namespace) }
            end

            context "with non-existent path" do
              let(:path) { "nonexistent" }

              it { is_expected.to be_nil }
            end

            context "with partially valid path" do
              let(:path) { "api.nonexistent" }

              it { is_expected.to be_nil }
            end
          end
        end

        describe "counting methods" do
          let(:deeply_nested_namespace) do
            described_class.new(
              name: :timing,
              metrics: {
                duration: metric_def1,
                latency: metric_def2
              }
            )
          end

          let(:api_namespace) do
            described_class.new(
              name: :api,
              metrics: {
                requests: metric_def1
              },
              namespaces: {
                timing: deeply_nested_namespace
              }
            )
          end

          let(:web_namespace) do
            described_class.new(
              name: :web,
              metrics: {
                page_views: metric_def1
              },
              namespaces: {
                api: api_namespace
              }
            )
          end

          describe "#total_metrics_count" do
            context "for namespace with nested metrics" do
              subject { web_namespace.total_metrics_count }

              # web: 1 metric + api: 1 metric + timing: 2 metrics = 4 total
              it { is_expected.to eq(4) }
            end

            context "for leaf namespace" do
              subject { deeply_nested_namespace.total_metrics_count }

              it { is_expected.to eq(2) }
            end
          end

          describe "#total_namespaces_count" do
            context "for namespace with nested namespaces" do
              subject { web_namespace.total_namespaces_count }

              # web has 1 direct namespace (api), api has 1 (timing) = 2 total
              it { is_expected.to eq(2) }
            end

            context "for namespace with no children" do
              subject { deeply_nested_namespace.total_namespaces_count }

              it { is_expected.to eq(0) }
            end
          end
        end
      end
    end
  end
end
