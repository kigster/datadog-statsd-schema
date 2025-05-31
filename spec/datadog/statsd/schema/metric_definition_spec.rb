# frozen_string_literal: true

RSpec.describe Datadog::Statsd::Schema::MetricDefinition do
  describe 'initialization' do
    it 'creates a metric definition with required attributes' do
      metric = described_class.new(name: :page_views, type: :counter)

      expect(metric.name).to eq(:page_views)
      expect(metric.type).to eq(:counter)
      expect(metric.description).to be_nil
      expect(metric.allowed_tags).to eq([])
      expect(metric.required_tags).to eq([])
      expect(metric.inherit_tags).to be_nil
      expect(metric.units).to be_nil
    end

    it 'accepts all optional attributes' do
      metric = described_class.new(
        name: :request_duration,
        type: :distribution,
        description: 'HTTP request processing time',
        allowed_tags: %i[controller action method],
        required_tags: %i[controller],
        inherit_tags: 'web.request.total',
        units: 'milliseconds'
      )

      expect(metric.name).to eq(:request_duration)
      expect(metric.type).to eq(:distribution)
      expect(metric.description).to eq('HTTP request processing time')
      expect(metric.allowed_tags).to eq(%i[controller action method])
      expect(metric.required_tags).to eq(%i[controller])
      expect(metric.inherit_tags).to eq('web.request.total')
      expect(metric.units).to eq('milliseconds')
    end

    it 'validates metric type' do
      expect do
        described_class.new(name: :invalid, type: :invalid_type)
      end.to raise_error(Dry::Struct::Error, /invalid_type.*failed/)
    end

    it 'accepts all valid metric types' do
      Datadog::Statsd::Schema::MetricDefinition::VALID_METRIC_TYPES.each do |type|
        expect do
          described_class.new(name: :test_metric, type: type)
        end.not_to raise_error
      end
    end
  end

  describe '#full_name' do
    let(:metric) { described_class.new(name: :duration, type: :timing) }

    it 'returns just the name when no namespace path provided' do
      expect(metric.full_name).to eq('duration')
      expect(metric.full_name([])).to eq('duration')
    end

    it 'builds full name with namespace path' do
      expect(metric.full_name(%w[web request])).to eq('web.request.duration')
    end

    it 'handles single namespace' do
      expect(metric.full_name(['api'])).to eq('api.duration')
    end
  end

  describe '#allows_tag?' do
    context 'with no allowed tags restrictions' do
      let(:metric) { described_class.new(name: :test, type: :counter) }

      it 'allows any tag' do
        expect(metric.allows_tag?(:any_tag)).to be true
        expect(metric.allows_tag?('string_tag')).to be true
      end
    end

    context 'with allowed tags restrictions' do
      let(:metric) do
        described_class.new(
          name: :test,
          type: :counter,
          allowed_tags: %i[controller action method]
        )
      end

      it 'allows specified tags' do
        expect(metric.allows_tag?(:controller)).to be true
        expect(metric.allows_tag?('action')).to be true
        expect(metric.allows_tag?(:method)).to be true
      end

      it 'rejects non-specified tags' do
        expect(metric.allows_tag?(:status_code)).to be false
        expect(metric.allows_tag?('region')).to be false
      end
    end
  end

  describe '#requires_tag?' do
    let(:metric) do
      described_class.new(
        name: :test,
        type: :counter,
        required_tags: %i[controller action]
      )
    end

    it 'returns true for required tags' do
      expect(metric.requires_tag?(:controller)).to be true
      expect(metric.requires_tag?('action')).to be true
    end

    it 'returns false for non-required tags' do
      expect(metric.requires_tag?(:method)).to be false
      expect(metric.requires_tag?('region')).to be false
    end
  end

  describe '#missing_required_tags' do
    let(:metric) do
      described_class.new(
        name: :test,
        type: :counter,
        required_tags: %i[controller action method]
      )
    end

    it 'returns empty array when all required tags provided' do
      tags = { controller: 'home', action: 'index', method: 'get' }
      expect(metric.missing_required_tags(tags)).to eq([])
    end

    it 'returns missing tags' do
      tags = { controller: 'home' }
      expect(metric.missing_required_tags(tags)).to match_array(%i[action method])
    end

    it 'handles string keys' do
      tags = { 'controller' => 'home', 'action' => 'index' }
      expect(metric.missing_required_tags(tags)).to eq([:method])
    end

    it 'returns all required tags when none provided' do
      expect(metric.missing_required_tags({})).to match_array(%i[controller action method])
    end
  end

  describe '#invalid_tags' do
    context 'with no tag restrictions' do
      let(:metric) { described_class.new(name: :test, type: :counter) }

      it 'returns empty array for any tags' do
        tags = { any_tag: 'value', another: 'value' }
        expect(metric.invalid_tags(tags)).to eq([])
      end
    end

    context 'with allowed tags restrictions' do
      let(:metric) do
        described_class.new(
          name: :test,
          type: :counter,
          allowed_tags: %i[controller action]
        )
      end

      it 'returns empty array for valid tags' do
        tags = { controller: 'home', action: 'index' }
        expect(metric.invalid_tags(tags)).to eq([])
      end

      it 'returns invalid tags' do
        tags = { controller: 'home', action: 'index', method: 'get', region: 'us' }
        expect(metric.invalid_tags(tags)).to match_array(%i[method region])
      end

      it 'handles string keys' do
        tags = { 'controller' => 'home', 'invalid_tag' => 'value' }
        expect(metric.invalid_tags(tags)).to eq([:invalid_tag])
      end
    end
  end

  describe '#valid_tags?' do
    let(:metric) do
      described_class.new(
        name: :test,
        type: :counter,
        allowed_tags: %i[controller action method],
        required_tags: %i[controller]
      )
    end

    it 'returns true for valid tag sets' do
      tags = { controller: 'home', action: 'index' }
      expect(metric.valid_tags?(tags)).to be true
    end

    it 'returns false when required tags missing' do
      tags = { action: 'index' }
      expect(metric.valid_tags?(tags)).to be false
    end

    it 'returns false when invalid tags present' do
      tags = { controller: 'home', invalid_tag: 'value' }
      expect(metric.valid_tags?(tags)).to be false
    end

    it 'returns false for both missing required and invalid tags' do
      tags = { invalid_tag: 'value' }
      expect(metric.valid_tags?(tags)).to be false
    end
  end

  describe 'metric type predicates' do
    describe '#timing_metric?' do
      it 'returns true for timing-based metrics' do
        %i[timing distribution histogram].each do |type|
          metric = described_class.new(name: :test, type: type)
          expect(metric.timing_metric?).to be true
        end
      end

      it 'returns false for non-timing metrics' do
        %i[counter gauge set].each do |type|
          metric = described_class.new(name: :test, type: type)
          expect(metric.timing_metric?).to be false
        end
      end
    end

    describe '#counting_metric?' do
      it 'returns true for counter metrics' do
        metric = described_class.new(name: :test, type: :counter)
        expect(metric.counting_metric?).to be true
      end

      it 'returns false for non-counter metrics' do
        %i[gauge timing distribution histogram set].each do |type|
          metric = described_class.new(name: :test, type: type)
          expect(metric.counting_metric?).to be false
        end
      end
    end

    describe '#gauge_metric?' do
      it 'returns true for gauge metrics' do
        metric = described_class.new(name: :test, type: :gauge)
        expect(metric.gauge_metric?).to be true
      end

      it 'returns false for non-gauge metrics' do
        %i[counter timing distribution histogram set].each do |type|
          metric = described_class.new(name: :test, type: type)
          expect(metric.gauge_metric?).to be false
        end
      end
    end

    describe '#set_metric?' do
      it 'returns true for set metrics' do
        metric = described_class.new(name: :test, type: :set)
        expect(metric.set_metric?).to be true
      end

      it 'returns false for non-set metrics' do
        %i[counter gauge timing distribution histogram].each do |type|
          metric = described_class.new(name: :test, type: type)
          expect(metric.set_metric?).to be false
        end
      end
    end
  end

  describe 'tag inheritance' do
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
        inherit_tags: 'web.parent'
      )
    end

    let(:schema_registry) do
      double('schema_registry').tap do |registry|
        allow(registry).to receive(:find_metric).with('web.parent').and_return(parent_metric)
      end
    end

    describe '#effective_allowed_tags' do
      it 'returns own tags when no inheritance' do
        expect(parent_metric.effective_allowed_tags).to eq(%i[controller action])
      end

      it 'returns own tags when no schema registry provided' do
        expect(child_metric.effective_allowed_tags).to eq(%i[method status_code])
      end

      it 'merges inherited and own tags' do
        result = child_metric.effective_allowed_tags(schema_registry)
        expect(result).to match_array(%i[controller action method status_code])
      end

      it 'handles missing inherited metric gracefully' do
        allow(schema_registry).to receive(:find_metric).and_return(nil)
        expect(child_metric.effective_allowed_tags(schema_registry)).to eq(%i[method status_code])
      end
    end

    describe '#effective_required_tags' do
      it 'returns own tags when no inheritance' do
        expect(parent_metric.effective_required_tags).to eq(%i[controller])
      end

      it 'returns own tags when no schema registry provided' do
        expect(child_metric.effective_required_tags).to eq(%i[method])
      end

      it 'merges inherited and own required tags' do
        result = child_metric.effective_required_tags(schema_registry)
        expect(result).to match_array(%i[controller method])
      end

      it 'handles missing inherited metric gracefully' do
        allow(schema_registry).to receive(:find_metric).and_return(nil)
        expect(child_metric.effective_required_tags(schema_registry)).to eq(%i[method])
      end
    end
  end
end
