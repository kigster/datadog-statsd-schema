# frozen_string_literal: true

# Shared examples for dry-struct initialization patterns
RSpec.shared_examples "a dry-struct with defaults" do |required_attributes, default_expectations|
  describe "initialization" do
    subject { described_class.new(required_attributes) }

    it "creates successfully with required attributes" do
      expect { subject }.not_to raise_error
    end

    default_expectations.each do |attribute, expected_value|
      its(attribute) { is_expected.to eq(expected_value) }
    end
  end
end

# Shared examples for finder methods that accept symbol or string
RSpec.shared_examples "a finder method" do |method_name, items_hash, existing_key, nonexistent_key|
  describe "##{method_name}" do
    subject { described_class.new(items_hash) }

    context "with existing item" do
      it "finds by symbol" do
        expect(subject.public_send(method_name, existing_key)).to eq(items_hash[existing_key])
      end

      it "finds by string" do
        expect(subject.public_send(method_name, existing_key.to_s)).to eq(items_hash[existing_key])
      end
    end

    context "with non-existent item" do
      its(method_name, nonexistent_key) { is_expected.to be_nil }
    end
  end
end

# Shared examples for existence check methods
RSpec.shared_examples "an existence checker" do |method_name, items_hash, existing_key, nonexistent_key|
  describe "##{method_name}" do
    subject { described_class.new(items_hash) }

    context "with existing item" do
      its(method_name, existing_key) { is_expected.to be true }
      its(method_name, existing_key.to_s) { is_expected.to be true }
    end

    context "with non-existent item" do
      its(method_name, nonexistent_key) { is_expected.to be false }
    end
  end
end

# Shared examples for collection name getters
RSpec.shared_examples "a collection names getter" do |method_name, items_hash, expected_names|
  describe "##{method_name}" do
    subject { described_class.new(items_hash) }

    its(method_name) { is_expected.to match_array(expected_names) }
  end
end

# Shared examples for validation methods that return arrays of errors
RSpec.shared_examples "a validation method" do |method_name, valid_setup, invalid_setup, expected_errors|
  describe "##{method_name}" do
    context "with valid setup" do
      subject { described_class.new(valid_setup) }

      its(method_name) { is_expected.to eq([]) }
    end

    context "with invalid setup" do
      subject { described_class.new(invalid_setup) }

      its(method_name) { is_expected.to include(*expected_errors) }
    end
  end
end

# Shared examples for metric type predicates
RSpec.shared_examples "a metric type predicate" do |method_name, matching_types, non_matching_types|
  describe "##{method_name}" do
    context "with matching types" do
      matching_types.each do |type|
        context "when type is #{type}" do
          subject { described_class.new(name: :test, type: type) }

          its(method_name) { is_expected.to be true }
        end
      end
    end

    context "with non-matching types" do
      non_matching_types.each do |type|
        context "when type is #{type}" do
          subject { described_class.new(name: :test, type: type) }

          its(method_name) { is_expected.to be false }
        end
      end
    end
  end
end

# Shared examples for tag validation
RSpec.shared_examples "tag value validation" do |tag_setup, valid_values, invalid_values|
  let(:tag) { described_class.new(tag_setup) }

  context "with valid values" do
    valid_values.each do |value|
      it "accepts #{value.inspect}" do
        expect(tag.allows_value?(value)).to be true
      end
    end
  end

  context "with invalid values" do
    invalid_values.each do |value|
      it "rejects #{value.inspect}" do
        expect(tag.allows_value?(value)).to be false
      end
    end
  end
end

# Shared examples for immutable updates
RSpec.shared_examples "an immutable update method" do |method_name, initial_state, update_arg, expected_change|
  describe "##{method_name}" do
    subject { described_class.new(initial_state) }

    it "returns a new instance" do
      result = subject.public_send(method_name, update_arg)
      expect(result).not_to eq(subject)
      expect(result.class).to eq(subject.class)
    end

    it "leaves original unchanged" do
      original_state = subject.attributes.dup
      subject.public_send(method_name, update_arg)
      expect(subject.attributes).to eq(original_state)
    end

    it "applies expected change" do
      result = subject.public_send(method_name, update_arg)
      expected_change.each do |attribute, expected_value|
        expect(result.public_send(attribute)).to eq(expected_value)
      end
    end
  end
end

# Shared examples for path-based finders
RSpec.shared_examples "a path-based finder" do |method_name, setup, test_cases|
  describe "##{method_name}" do
    subject { described_class.new(setup) }

    test_cases.each do |path, expected_result|
      context "with path '#{path}'" do
        if expected_result.nil?
          its(method_name, path) { is_expected.to be_nil }
        else
          it "finds the correct item" do
            expect(subject.public_send(method_name, path)).to eq(expected_result)
          end
        end
      end
    end
  end
end
