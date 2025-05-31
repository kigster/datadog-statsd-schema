# frozen_string_literal: true

RSpec.describe Datadog::Statsd::Schema::TagDefinition do
  describe 'initialization' do
    it 'creates a tag definition with required name' do
      tag = described_class.new(name: :controller)
      expect(tag.name).to eq(:controller)
      expect(tag.type).to eq(:string)
      expect(tag.transform).to eq([])
      expect(tag.values).to be_nil
      expect(tag.validate).to be_nil
    end

    it 'accepts all optional attributes' do
      custom_validator = ->(val) { val.length > 3 }
      tag = described_class.new(
        name: :status_code,
        values: [200, 404, 500],
        type: :integer,
        transform: %i[downcase underscore],
        validate: custom_validator
      )

      expect(tag.name).to eq(:status_code)
      expect(tag.values).to eq([200, 404, 500])
      expect(tag.type).to eq(:integer)
      expect(tag.transform).to eq(%i[downcase underscore])
      expect(tag.validate).to eq(custom_validator)
    end
  end

  describe '#allows_value?' do
    context 'with no value restrictions' do
      let(:tag) { described_class.new(name: :any_tag) }

      it 'allows any value' do
        expect(tag.allows_value?('anything')).to be true
        expect(tag.allows_value?(123)).to be true
        expect(tag.allows_value?(:symbol)).to be true
      end
    end

    context 'with array values' do
      let(:tag) { described_class.new(name: :method, values: %w[get post put]) }

      it 'allows values in the array' do
        expect(tag.allows_value?('get')).to be true
        expect(tag.allows_value?('post')).to be true
      end

      it 'allows symbol/string variations' do
        expect(tag.allows_value?(:get)).to be true
        expect(tag.allows_value?('get')).to be true
      end

      it 'rejects values not in array' do
        expect(tag.allows_value?('delete')).to be false
        expect(tag.allows_value?('patch')).to be false
      end
    end

    context 'with regexp values' do
      let(:tag) { described_class.new(name: :controller, values: /^[a-z_]+$/) }

      it 'allows matching values' do
        expect(tag.allows_value?('home_controller')).to be true
        expect(tag.allows_value?('users')).to be true
      end

      it 'rejects non-matching values' do
        expect(tag.allows_value?('HomeController')).to be false
        expect(tag.allows_value?('123invalid')).to be false
      end
    end

    context 'with proc values' do
      let(:tag) { described_class.new(name: :score, values: ->(val) { val.to_i.between?(0, 100) }) }

      it 'uses proc for validation' do
        expect(tag.allows_value?(50)).to be true
        expect(tag.allows_value?('75')).to be true
        expect(tag.allows_value?(150)).to be false
        expect(tag.allows_value?(-10)).to be false
      end
    end
  end

  describe '#transform_value' do
    let(:transformers) do
      {
        downcase:   ->(val) { val.to_s.downcase },
        underscore: ->(val) { val.to_s.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '') }
      }
    end

    context 'with no transformations' do
      let(:tag) { described_class.new(name: :simple) }

      it 'returns value unchanged' do
        expect(tag.transform_value('SomeValue', transformers)).to eq('SomeValue')
      end
    end

    context 'with single transformation' do
      let(:tag) { described_class.new(name: :controller, transform: [:downcase]) }

      it 'applies transformation' do
        expect(tag.transform_value('HomeController', transformers)).to eq('homecontroller')
      end
    end

    context 'with chained transformations' do
      let(:tag) { described_class.new(name: :controller, transform: %i[underscore downcase]) }

      it 'applies transformations in order' do
        expect(tag.transform_value('HomeController', transformers)).to eq('home_controller')
      end
    end

    context 'with missing transformer' do
      let(:tag) { described_class.new(name: :controller, transform: [:missing_transformer]) }

      it 'skips missing transformers' do
        expect(tag.transform_value('SomeValue', transformers)).to eq('SomeValue')
      end
    end
  end

  describe '#valid_value?' do
    let(:transformers) do
      {
        downcase: ->(val) { val.to_s.downcase }
      }
    end

    context 'with string type' do
      let(:tag) { described_class.new(name: :name, type: :string) }

      it 'accepts any value' do
        expect(tag.valid_value?('test', transformers)).to be true
        expect(tag.valid_value?(123, transformers)).to be true
      end
    end

    context 'with integer type' do
      let(:tag) { described_class.new(name: :count, type: :integer) }

      it 'accepts integer values' do
        expect(tag.valid_value?(123, transformers)).to be true
        expect(tag.valid_value?('456', transformers)).to be true
      end

      it 'rejects non-integer values' do
        expect(tag.valid_value?('abc', transformers)).to be false
        expect(tag.valid_value?('12.5', transformers)).to be false
      end
    end

    context 'with custom validation' do
      let(:tag) do
        described_class.new(
          name: :status_code,
          type: :integer,
          validate: ->(code) { (100..599).include?(code.to_i) }
        )
      end

      it 'applies custom validation' do
        expect(tag.valid_value?(200, transformers)).to be true
        expect(tag.valid_value?(404, transformers)).to be true
        expect(tag.valid_value?(50, transformers)).to be false
        expect(tag.valid_value?(700, transformers)).to be false
      end
    end

    context 'with transformations and values' do
      let(:tag) do
        described_class.new(
          name: :method,
          values: %w[get post put],
          transform: [:downcase]
        )
      end

      it 'validates after transformation' do
        expect(tag.valid_value?('GET', transformers)).to be true
        expect(tag.valid_value?('POST', transformers)).to be true
        expect(tag.valid_value?('DELETE', transformers)).to be false
      end
    end
  end
end
