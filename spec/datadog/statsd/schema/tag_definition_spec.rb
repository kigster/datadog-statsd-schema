# frozen_string_literal: true

require "spec_helper"

module Datadog
  class Statsd
    module Schema
      RSpec.describe TagDefinition do
        subject { described_class }

        describe ".new" do
          context "with required name only" do
            subject { described_class.new(name: :controller) }

            its(:name) { is_expected.to eq(:controller) }
            its(:type) { is_expected.to eq(:string) }
            its(:transform) { is_expected.to eq([]) }
            its(:values) { is_expected.to be_nil }
            its(:validate) { is_expected.to be_nil }
          end

          context "with all optional attributes" do
            subject do
              described_class.new(
                name: :status_code,
                values: [200, 404, 500],
                type: :integer,
                transform: %i[downcase underscore],
                validate: custom_validator
              )
            end

            let(:custom_validator) { ->(val) { val.length > 3 } }

            its(:name) { is_expected.to eq(:status_code) }
            its(:values) { is_expected.to eq([200, 404, 500]) }
            its(:type) { is_expected.to eq(:integer) }
            its(:transform) { is_expected.to eq(%i[downcase underscore]) }
            its(:validate) { is_expected.to eq(custom_validator) }
          end
        end

        describe "#allows_value?" do
          subject { tag.allows_value?(value) }

          context "with no value restrictions" do
            let(:tag) { described_class.new(name: :any_tag) }

            context "with string value" do
              let(:value) { "anything" }

              it { is_expected.to be true }
            end

            context "with integer value" do
              let(:value) { 123 }

              it { is_expected.to be true }
            end

            context "with symbol value" do
              let(:value) { :symbol }

              it { is_expected.to be true }
            end
          end

          context "with array values" do
            let(:tag) { described_class.new(name: :method, values: %w[get post put]) }

            context "with allowed string value" do
              let(:value) { "get" }

              it { is_expected.to be true }
            end

            context "with another allowed string value" do
              let(:value) { "post" }

              it { is_expected.to be true }
            end

            context "with allowed symbol value" do
              let(:value) { :get }

              it { is_expected.to be true }
            end

            context "with allowed value as string when symbol provided" do
              let(:value) { "get" }

              it { is_expected.to be true }
            end

            context "with disallowed string value" do
              let(:value) { "delete" }

              it { is_expected.to be false }
            end

            context "with another disallowed value" do
              let(:value) { "patch" }

              it { is_expected.to be false }
            end
          end

          context "with regexp values" do
            let(:tag) { described_class.new(name: :controller, values: /^[a-z_]+$/) }

            context "with matching snake_case value" do
              let(:value) { "home_controller" }

              it { is_expected.to be true }
            end

            context "with matching lowercase value" do
              let(:value) { "users" }

              it { is_expected.to be true }
            end

            context "with non-matching PascalCase value" do
              let(:value) { "HomeController" }

              it { is_expected.to be false }
            end

            context "with non-matching numeric value" do
              let(:value) { "123invalid" }

              it { is_expected.to be false }
            end
          end

          context "with proc values" do
            let(:tag) do
              described_class.new(name: :score, values: ->(val) { val.to_i.between?(0, 100) })
            end

            context "with valid integer in range" do
              let(:value) { 50 }

              it { is_expected.to be true }
            end

            context "with valid string number in range" do
              let(:value) { "75" }

              it { is_expected.to be true }
            end

            context "with integer above range" do
              let(:value) { 150 }

              it { is_expected.to be false }
            end

            context "with integer below range" do
              let(:value) { -10 }

              it { is_expected.to be false }
            end
          end
        end

        describe "#transform_value" do
          subject { tag.transform_value(input_value, transformers) }

          let(:transformers) do
            {
              downcase: ->(val) { val.to_s.downcase },
              underscore: ->(val) { val.to_s.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, "") }
            }
          end

          context "with no transformations" do
            let(:tag) { described_class.new(name: :simple) }
            let(:input_value) { "SomeValue" }

            it { is_expected.to eq("SomeValue") }
          end

          context "with single transformation" do
            let(:tag) { described_class.new(name: :controller, transform: [:downcase]) }
            let(:input_value) { "HomeController" }

            it { is_expected.to eq("homecontroller") }
          end

          context "with chained transformations" do
            let(:tag) { described_class.new(name: :controller, transform: %i[underscore downcase]) }
            let(:input_value) { "HomeController" }

            it { is_expected.to eq("home_controller") }
          end

          context "with missing transformer" do
            let(:tag) { described_class.new(name: :controller, transform: [:missing_transformer]) }
            let(:input_value) { "SomeValue" }

            it { is_expected.to eq("SomeValue") }
          end
        end

        describe "#valid_value?" do
          subject { tag.valid_value?(input_value, transformers) }

          let(:transformers) { { downcase: ->(val) { val.to_s.downcase } } }

          context "with string type" do
            let(:tag) { described_class.new(name: :name, type: :string) }

            context "with string value" do
              let(:input_value) { "test" }

              it { is_expected.to be true }
            end

            context "with integer value" do
              let(:input_value) { 123 }

              it { is_expected.to be true }
            end
          end

          context "with integer type" do
            let(:tag) { described_class.new(name: :count, type: :integer) }

            context "with integer value" do
              let(:input_value) { 123 }

              it { is_expected.to be true }
            end

            context "with numeric string value" do
              let(:input_value) { "456" }

              it { is_expected.to be true }
            end

            context "with non-numeric string value" do
              let(:input_value) { "abc" }

              it { is_expected.to be false }
            end

            context "with decimal string value" do
              let(:input_value) { "12.5" }

              it { is_expected.to be false }
            end
          end

          context "with custom validation" do
            let(:tag) do
              described_class.new(
                name: :status_code,
                type: :integer,
                validate: ->(code) { (100..599).include?(code.to_i) }
              )
            end

            context "with valid status code" do
              let(:input_value) { 200 }

              it { is_expected.to be true }
            end

            context "with another valid status code" do
              let(:input_value) { 404 }

              it { is_expected.to be true }
            end

            context "with status code below range" do
              let(:input_value) { 50 }

              it { is_expected.to be false }
            end

            context "with status code above range" do
              let(:input_value) { 700 }

              it { is_expected.to be false }
            end
          end

          context "with transformations and values" do
            let(:tag) do
              described_class.new(name: :method, values: %w[get post put], transform: [:downcase])
            end

            context "with uppercase value that transforms to valid" do
              let(:input_value) { "GET" }

              it { is_expected.to be true }
            end

            context "with mixed case value that transforms to valid" do
              let(:input_value) { "POST" }

              it { is_expected.to be true }
            end

            context "with uppercase value that transforms to invalid" do
              let(:input_value) { "DELETE" }

              it { is_expected.to be false }
            end
          end
        end
      end
    end
  end
end
