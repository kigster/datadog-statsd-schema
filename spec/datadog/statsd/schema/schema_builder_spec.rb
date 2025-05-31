# frozen_string_literal: true

require "spec_helper"

module Datadog
  class Statsd
    module Schema
      RSpec.describe SchemaBuilder do
        subject { described_class }

        describe ".new" do
          subject { described_class.new }

          its(:transformers) { is_expected.to eq({}) }
          its("root_namespace.name") { is_expected.to eq(:root) }
          its("root_namespace.namespaces") { is_expected.to eq({}) }
        end

        describe "#transformers" do
          subject { builder }

          let(:builder) { described_class.new }

          context "when called without block" do
            subject { builder.transformers }

            it { is_expected.to eq({}) }
          end

          context "when defining transformers using DSL" do
            before do
              builder.transformers do
                underscore { |text| text.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, "") }
                downcase { |text| text.downcase }
              end
            end

            describe "underscore transformer" do
              subject { builder.transformers[:underscore] }

              its(:class) { is_expected.to eq(Proc) }

              it "transforms PascalCase to snake_case" do
                expect(subject.call("HomeController")).to eq("home_controller")
              end
            end

            describe "downcase transformer" do
              subject { builder.transformers[:downcase] }

              its(:class) { is_expected.to eq(Proc) }

              it "transforms text to lowercase" do
                expect(subject.call("HELLO")).to eq("hello")
              end
            end
          end

          context "when accepting lambda syntax" do
            let(:downcase_proc) { ->(text) { text.downcase } }

            before do
              proc_ref = downcase_proc # Capture the proc in a local variable
              builder.transformers { downcase proc_ref }
            end

            describe "lambda transformer" do
              subject { builder.transformers[:downcase] }

              it { is_expected.to eq(downcase_proc) }
            end
          end
        end

        describe "#namespace" do
          subject { builder }

          let(:builder) { described_class.new }

          context "with simple namespace definition" do
            before do
              builder.namespace :web do
                description "Web application metrics"
              end
            end

            describe "root namespace" do
              subject { builder.root_namespace }

              it "has web namespace" do
                expect(subject.find_namespace(:web)).not_to be_nil
              end
            end

            describe "web namespace" do
              subject { builder.root_namespace.find_namespace(:web) }

              its(:name) { is_expected.to eq(:web) }
              its(:description) { is_expected.to eq("Web application metrics") }
            end
          end

          context "with nested namespaces" do
            before do
              builder.namespace :web do
                namespace :api do
                  description "API metrics"
                end
              end
            end

            describe "web namespace" do
              subject { builder.root_namespace.find_namespace(:web) }

              it { is_expected.not_to be_nil }

              describe "api namespace" do
                subject { builder.root_namespace.find_namespace(:web).find_namespace(:api) }

                its(:name) { is_expected.to eq(:api) }
                its(:description) { is_expected.to eq("API metrics") }
              end
            end
          end
        end

        describe "#validate!" do
          subject { builder }

          let(:builder) { described_class.new }

          context "with valid schema" do
            before do
              builder.namespace :web do
                tags { tag :controller, values: %w[home users] }

                metrics { counter :page_views, tags: { required: %w[controller] } }
              end
            end

            it "does not raise error" do
              expect { subject.validate! }.not_to raise_error
            end
          end

          context "with invalid tag references" do
            before do
              builder.namespace :web do
                tags { tag :controller, values: %w[home users] }

                metrics { counter :page_views, tags: { required: %w[nonexistent_tag] } }
              end
            end

            it "raises schema error" do
              expect { subject.validate! }.to raise_error(
                Datadog::Statsd::Schema::SchemaError,
                /Schema validation failed.*nonexistent_tag/
              )
            end
          end
        end

        describe "complete schema definition" do
          subject { schema }

          let(:schema) do
            described_class
              .new
              .tap do |builder|
                builder.transformers do
                  underscore { |text| text.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, "") }
                  downcase { |text| text.downcase }
                end

                builder.namespace :web do
                  description "Web application metrics"

                  tags do
                    tag :controller,
                        values: %w[home users posts],
                        transform: %i[underscore downcase]
                    tag :action, values: %w[index show create update destroy]
                    tag :method, values: %i[get post put patch delete], type: :symbol
                    tag :status_code,
                        type: :integer,
                        validate: ->(code) { (100..599).include?(code.to_i) }
                  end

                  metrics do
                    counter :page_views,
                            description: "Number of page views",
                            tags: {
                              allowed: %w[controller action method],
                              required: %w[controller]
                            }

                    distribution :request_duration,
                                 description: "Request processing time",
                                 units: "milliseconds",
                                 tags: {
                                   allowed: %w[controller action method status_code],
                                   required: %w[controller]
                                 }

                    namespace :api do
                      counter :requests,
                              description: "API requests count",
                              inherit_tags: "web.page_views"
                    end
                  end

                  namespace :database do
                    tags do
                      tag :table, values: %w[users posts comments]
                      tag :operation, values: %w[select insert update delete]
                    end

                    metrics do
                      histogram :query_duration,
                                description: "Database query time",
                                tags: {
                                  allowed: %w[table operation],
                                  required: %w[table]
                                }
                    end
                  end
                end
              end
              .build
          end

          let(:web_namespace) { schema.find_namespace(:web) }
          let(:database_namespace) { web_namespace.find_namespace(:database) }

          describe "root namespace" do
            its(:name) { is_expected.to eq(:root) }
            its("namespaces.keys") { is_expected.to eq([:web]) }
          end

          describe "web namespace structure" do
            subject { web_namespace }

            its(:description) { is_expected.to eq("Web application metrics") }
            its(:tag_names) { is_expected.to match_array(%i[controller action method status_code]) }

            its(:metric_names) do
              is_expected.to match_array(%i[page_views request_duration api_requests])
            end

            its(:namespace_names) { is_expected.to eq([:database]) }
          end

          describe "web namespace tags" do
            describe "controller tag" do
              subject { web_namespace.find_tag(:controller) }

              its(:values) { is_expected.to eq(%w[home users posts]) }
              its(:transform) { is_expected.to eq(%i[underscore downcase]) }
            end

            describe "status_code tag" do
              subject { web_namespace.find_tag(:status_code) }

              its(:type) { is_expected.to eq(:integer) }
              its(:validate) { is_expected.to be_a(Proc) }
            end
          end

          describe "web namespace metrics" do
            describe "page_views metric" do
              subject { web_namespace.find_metric(:page_views) }

              its(:type) { is_expected.to eq(:counter) }
              its(:description) { is_expected.to eq("Number of page views") }
              its(:allowed_tags) { is_expected.to match_array(%i[controller action method]) }
              its(:required_tags) { is_expected.to eq([:controller]) }
            end

            describe "request_duration metric" do
              subject { web_namespace.find_metric(:request_duration) }

              its(:type) { is_expected.to eq(:distribution) }
              its(:units) { is_expected.to eq("milliseconds") }

              its(:allowed_tags) do
                is_expected.to match_array(%i[controller action method status_code])
              end
            end

            describe "api_requests metric" do
              subject { web_namespace.find_metric(:api_requests) }

              its(:type) { is_expected.to eq(:counter) }
              its(:inherit_tags) { is_expected.to eq("web.page_views") }
            end
          end

          describe "database namespace structure" do
            subject { database_namespace }

            its(:tag_names) { is_expected.to match_array(%i[table operation]) }
            its(:metric_names) { is_expected.to eq([:query_duration]) }
          end

          describe "database namespace tags" do
            describe "table tag" do
              subject { database_namespace.find_tag(:table) }

              its(:values) { is_expected.to eq(%w[users posts comments]) }
            end
          end

          describe "database namespace metrics" do
            describe "query_duration metric" do
              subject { database_namespace.find_metric(:query_duration) }

              its(:type) { is_expected.to eq(:histogram) }
              its(:allowed_tags) { is_expected.to match_array(%i[table operation]) }
              its(:required_tags) { is_expected.to eq([:table]) }
            end
          end

          describe "metric full names" do
            subject { web_namespace.all_metrics.keys }

            it { is_expected.to include("web.page_views") }
            it { is_expected.to include("web.request_duration") }
            it { is_expected.to include("web.api_requests") }
            it { is_expected.to include("web.database.query_duration") }
          end
        end

        describe "metric block syntax" do
          subject { schema }

          let(:schema) do
            described_class
              .new
              .tap do |builder|
                builder.namespace :web do
                  tags do
                    tag :controller, values: %w[home users]
                    tag :action, values: %w[index show]
                  end

                  metrics do
                    distribution :request_duration do
                      description "HTTP request processing time"
                      tags allowed: %w[controller action], required: %w[controller]
                      units "milliseconds"
                      inherit_tags "web.base_metric"
                    end
                  end
                end
              end
              .build
          end

          describe "request_duration metric" do
            subject { schema.find_namespace(:web).find_metric(:request_duration) }

            its(:description) { is_expected.to eq("HTTP request processing time") }
            its(:allowed_tags) { is_expected.to match_array(%i[controller action]) }
            its(:required_tags) { is_expected.to eq([:controller]) }
            its(:units) { is_expected.to eq("milliseconds") }
            its(:inherit_tags) { is_expected.to eq("web.base_metric") }
          end
        end

        describe "all metric types" do
          subject { test_namespace }

          let(:schema) do
            described_class
              .new
              .tap do |builder|
                builder.namespace :test do
                  metrics do
                    counter :page_views
                    gauge :memory_usage
                    histogram :response_time
                    distribution :latency
                    timing :duration
                    set :unique_users
                  end
                end
              end
              .build
          end

          let(:test_namespace) { schema.find_namespace(:test) }

          %i[counter gauge histogram distribution timing set].each do |metric_type|
            metric_name =
              case metric_type
              when :counter
                :page_views
              when :gauge
                :memory_usage
              when :histogram
                :response_time
              when :distribution
                :latency
              when :timing
                :duration
              when :set
                :unique_users
              end

            describe "#{metric_name} metric" do
              subject { test_namespace.find_metric(metric_name) }

              its(:type) { is_expected.to eq(metric_type) }
            end
          end
        end

        describe "nested metrics namespaces" do
          subject { web_namespace }

          let(:schema) do
            described_class
              .new
              .tap do |builder|
                builder.namespace :web do
                  metrics do
                    namespace :request do
                      counter :total
                      distribution :duration
                    end

                    counter :page_views
                  end
                end
              end
              .build
          end

          let(:web_namespace) { schema.find_namespace(:web) }

          describe "metric names with prefix" do
            its(:metric_names) { is_expected.to include(:request_total) }
            its(:metric_names) { is_expected.to include(:request_duration) }
            its(:metric_names) { is_expected.to include(:page_views) }
          end

          describe "request_total metric" do
            subject { web_namespace.find_metric(:request_total) }

            its(:type) { is_expected.to eq(:counter) }
          end

          describe "request_duration metric" do
            subject { web_namespace.find_metric(:request_duration) }

            its(:type) { is_expected.to eq(:distribution) }
          end
        end
      end
    end
  end
end
