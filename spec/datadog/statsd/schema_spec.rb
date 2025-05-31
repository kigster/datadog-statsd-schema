# frozen_string_literal: true

require "spec_helper"

module Datadog
  class Statsd
    module Schema
      RSpec.describe Schema do
        subject { described_class }

        describe "::VERSION" do
          subject { described_class::VERSION }

          it { is_expected.not_to be_nil }
        end

        describe ".new" do
          subject { described_class }

          context "when called with no block" do
            subject { described_class.new }

            its(:class) { is_expected.to eq(Datadog::Statsd::Schema::Namespace) }
            its(:name) { is_expected.to eq(:root) }
            its(:namespaces) { is_expected.to be_empty }
          end

          context "when called with DSL block" do
            subject { described_class.new(&schema_block) }

            let(:schema_block) do
              proc do
                transformers { downcase { |text| text.downcase } }

                namespace :web do
                  tags do
                    tag :controller, values: %w[home users posts]
                    tag :action, values: %w[index show create]
                  end

                  metrics do
                    counter :page_views,
                            description: "Page view counter",
                            tags: {
                              allowed: %w[controller action],
                              required: %w[controller]
                            }
                  end
                end
              end
            end

            its(:class) { is_expected.to eq(Datadog::Statsd::Schema::Namespace) }
            its(:name) { is_expected.to eq(:root) }

            describe "web namespace" do
              subject { described_class.new(&schema_block).find_namespace(:web) }

              it { is_expected.not_to be_nil }

              describe "controller tag" do
                subject do
                  described_class.new(&schema_block).find_namespace(:web).find_tag(:controller)
                end

                it { is_expected.not_to be_nil }
              end

              describe "page_views metric" do
                subject do
                  described_class.new(&schema_block).find_namespace(:web).find_metric(:page_views)
                end

                it { is_expected.not_to be_nil }
              end
            end
          end
        end

        describe ".load_file" do
          subject { described_class.load_file("schema.rb") }

          let(:schema_file_content) { <<~RUBY }
            transformers do
              downcase { |text| text.downcase }
            end

            namespace :web do
              description 'Web metrics'
            #{"  "}
              tags do
                tag :environment, values: %w[development production]
              end

              metrics do
                counter :requests, tags: { required: %w[environment] }
              end
            end
          RUBY

          before { allow(File).to receive(:read).with("schema.rb").and_return(schema_file_content) }

          its(:class) { is_expected.to eq(Datadog::Statsd::Schema::Namespace) }

          describe "web namespace" do
            subject { described_class.load_file("schema.rb").find_namespace(:web) }

            before do
              allow(File).to receive(:read).with("schema.rb").and_return(schema_file_content)
            end

            its(:description) { is_expected.to eq("Web metrics") }

            describe "environment tag" do
              subject do
                described_class.load_file("schema.rb").find_namespace(:web).find_tag(:environment)
              end

              before do
                allow(File).to receive(:read).with("schema.rb").and_return(schema_file_content)
              end

              it { is_expected.not_to be_nil }
            end

            describe "requests metric" do
              subject do
                described_class.load_file("schema.rb").find_namespace(:web).find_metric(:requests)
              end

              before do
                allow(File).to receive(:read).with("schema.rb").and_return(schema_file_content)
              end

              it { is_expected.not_to be_nil }
            end
          end
        end

        describe ".configure" do
          subject { described_class }

          let(:mock_statsd) { double("statsd") }
          let(:mock_schema) { double("schema") }
          let(:test_tags) { { env: "test" } }

          after { described_class.instance_variable_set(:@configuration, nil) }

          it "yields configuration object" do
            described_class.configure do |config|
              config.statsd = mock_statsd
              config.schema = mock_schema
              config.tags = test_tags
            end

            config = described_class.configuration
            expect(config.statsd).to eq(mock_statsd)
            expect(config.schema).to eq(mock_schema)
            expect(config.tags).to eq(test_tags)
          end
        end

        describe ".configuration" do
          subject { described_class.configuration }

          after { described_class.instance_variable_set(:@configuration, nil) }

          its(:class) { is_expected.to eq(Datadog::Statsd::Schema::Configuration) }
          its(:statsd) { is_expected.to be_nil }
          its(:schema) { is_expected.to be_nil }
          its(:tags) { is_expected.to eq({}) }

          context "when called multiple times" do
            it "returns the same instance" do
              config1 = described_class.configuration
              config2 = described_class.configuration
              expect(config1).to be(config2)
            end
          end
        end

        describe Datadog::Statsd::Schema::Configuration do
          subject { described_class.new }

          describe "default values" do
            its(:statsd) { is_expected.to be_nil }
            its(:schema) { is_expected.to be_nil }
            its(:tags) { is_expected.to eq({}) }
          end

          describe "setting values" do
            subject(:config) { described_class.new }

            let(:mock_statsd) { double("statsd") }
            let(:mock_schema) { double("schema") }
            let(:test_tags) { { region: "us-east-1" } }

            before do
              config.statsd = mock_statsd
              config.schema = mock_schema
              config.tags = test_tags
            end

            its(:statsd) { is_expected.to eq(mock_statsd) }
            its(:schema) { is_expected.to eq(mock_schema) }
            its(:tags) { is_expected.to eq(test_tags) }
          end
        end

        describe "README integration example" do
          subject { schema }

          let(:schema) do
            described_class.new do
              transformers do
                underscore { |text| text.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, "") }
                downcase { |text| text.downcase }
              end

              namespace :web do
                namespace :request do
                  tags do
                    tag :uri, values: /.*/
                    tag :logged_in, values: %w[logged_in logged_out]
                    tag :billing_plan, values: %w[premium trial free]
                    tag :controller, values: /[a-z.]*/, transform: %i[underscore downcase]
                    tag :action, values: /[a-z.]*/, transform: %i[underscore downcase]
                    tag :method,
                        values: %i[get post put patch delete head options trace connect],
                        transform: [:downcase]
                    tag :status_code,
                        type: :integer,
                        validate: ->(code) { (100..599).include?(code) }
                  end

                  metrics do
                    distribution :duration,
                                 description: "HTTP request processing time in milliseconds",
                                 tags: {
                                   allowed: %w[controller action method status_code],
                                   required: %w[controller]
                                 }

                    counter :total,
                            description: "Total number of requests received",
                            tags: {
                              allowed: %w[controller action method status_code],
                              required: %w[controller]
                            }
                  end
                end
              end
            end
          end

          let(:web_namespace) { schema.find_namespace(:web) }
          let(:request_namespace) { web_namespace.find_namespace(:request) }

          describe "schema structure" do
            it { is_expected.to be_a(Datadog::Statsd::Schema::Namespace) }

            describe "web namespace" do
              subject { web_namespace }

              it { is_expected.not_to be_nil }

              describe "request namespace" do
                subject { request_namespace }

                it { is_expected.not_to be_nil }
              end
            end
          end

          describe "tag definitions" do
            subject { request_namespace }

            %i[controller action method status_code].each do |tag_name|
              describe "#{tag_name} tag" do
                subject { request_namespace.find_tag(tag_name) }

                it { is_expected.not_to be_nil }
              end
            end
          end

          describe "metric definitions" do
            describe "duration metric" do
              subject { request_namespace.find_metric(:duration) }

              its(:type) { is_expected.to eq(:distribution) }

              its(:description) do
                is_expected.to eq("HTTP request processing time in milliseconds")
              end

              its(:required_tags) { is_expected.to eq([:controller]) }
            end

            describe "total metric" do
              subject { request_namespace.find_metric(:total) }

              its(:type) { is_expected.to eq(:counter) }
              its(:description) { is_expected.to eq("Total number of requests received") }
              its(:required_tags) { is_expected.to eq([:controller]) }
            end
          end

          describe "tag validation functionality" do
            let(:controller_tag) { request_namespace.find_tag(:controller) }
            let(:status_code_tag) { request_namespace.find_tag(:status_code) }

            describe "controller tag validation" do
              subject(:tag) { controller_tag }

              it "accepts snake_case values" do
                expect(tag.allows_value?("home_controller")).to be true
              end

              it "accepts CamelCase values (should be transformed)" do
                expect(tag.allows_value?("HomeController")).to be true
              end
            end

            describe "status_code tag validation" do
              subject(:tag) { status_code_tag }

              it "accepts valid HTTP status codes" do
                expect(tag.valid_value?(200)).to be true
              end

              it "rejects invalid status codes" do
                expect(tag.valid_value?(999)).to be false
              end
            end
          end
        end
      end
    end
  end
end
