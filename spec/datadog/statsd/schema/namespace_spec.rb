# frozen_string_literal: true

RSpec.describe Datadog::Statsd::Schema::Namespace do
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
      description: 'Request processing time',
      allowed_tags: %i[controller action],
      required_tags: %i[controller]
    )
  end

  describe 'initialization' do
    it 'creates a namespace with required name' do
      namespace = described_class.new(name: :web)

      expect(namespace.name).to eq(:web)
      expect(namespace.tags).to eq({})
      expect(namespace.metrics).to eq({})
      expect(namespace.namespaces).to eq({})
      expect(namespace.description).to be_nil
    end

    it 'accepts all optional attributes' do
      namespace = described_class.new(
        name: :api,
        description: 'API metrics namespace',
        tags: { controller: tag_def1 },
        metrics: { page_views: metric_def1 },
        namespaces: {}
      )

      expect(namespace.name).to eq(:api)
      expect(namespace.description).to eq('API metrics namespace')
      expect(namespace.tags).to eq({ controller: tag_def1 })
      expect(namespace.metrics).to eq({ page_views: metric_def1 })
    end
  end

  describe '#full_path' do
    let(:namespace) { described_class.new(name: :request) }

    it 'returns single element array when no parent path' do
      expect(namespace.full_path).to eq([:request])
      expect(namespace.full_path([])).to eq([:request])
    end

    it 'combines with parent path' do
      expect(namespace.full_path(%i[web api])).to eq(%i[web api request])
    end
  end

  describe 'finding elements' do
    let(:namespace) do
      described_class.new(
        name: :web,
        tags: { controller: tag_def1, action: tag_def2 },
        metrics: { page_views: metric_def1, request_duration: metric_def2 }
      )
    end

    describe '#find_metric' do
      it 'finds existing metrics by symbol' do
        expect(namespace.find_metric(:page_views)).to eq(metric_def1)
        expect(namespace.find_metric(:request_duration)).to eq(metric_def2)
      end

      it 'finds existing metrics by string' do
        expect(namespace.find_metric('page_views')).to eq(metric_def1)
      end

      it 'returns nil for non-existent metrics' do
        expect(namespace.find_metric(:nonexistent)).to be_nil
      end
    end

    describe '#find_tag' do
      it 'finds existing tags by symbol' do
        expect(namespace.find_tag(:controller)).to eq(tag_def1)
        expect(namespace.find_tag(:action)).to eq(tag_def2)
      end

      it 'finds existing tags by string' do
        expect(namespace.find_tag('controller')).to eq(tag_def1)
      end

      it 'returns nil for non-existent tags' do
        expect(namespace.find_tag(:nonexistent)).to be_nil
      end
    end

    describe '#find_namespace' do
      let(:nested_namespace) { described_class.new(name: :api) }
      let(:namespace_with_nested) do
        described_class.new(
          name: :web,
          namespaces: { api: nested_namespace }
        )
      end

      it 'finds existing nested namespaces' do
        expect(namespace_with_nested.find_namespace(:api)).to eq(nested_namespace)
        expect(namespace_with_nested.find_namespace('api')).to eq(nested_namespace)
      end

      it 'returns nil for non-existent namespaces' do
        expect(namespace_with_nested.find_namespace(:nonexistent)).to be_nil
      end
    end
  end

  describe 'adding elements' do
    let(:namespace) { described_class.new(name: :web) }

    describe '#add_metric' do
      it 'returns new namespace with added metric' do
        new_namespace = namespace.add_metric(metric_def1)

        expect(new_namespace).not_to eq(namespace) # immutable
        expect(new_namespace.metrics).to eq({ page_views: metric_def1 })
        expect(namespace.metrics).to eq({}) # original unchanged
      end
    end

    describe '#add_tag' do
      it 'returns new namespace with added tag' do
        new_namespace = namespace.add_tag(tag_def1)

        expect(new_namespace).not_to eq(namespace) # immutable
        expect(new_namespace.tags).to eq({ controller: tag_def1 })
        expect(namespace.tags).to eq({}) # original unchanged
      end
    end

    describe '#add_namespace' do
      let(:nested_namespace) { described_class.new(name: :api) }

      it 'returns new namespace with added nested namespace' do
        new_namespace = namespace.add_namespace(nested_namespace)

        expect(new_namespace).not_to eq(namespace) # immutable
        expect(new_namespace.namespaces).to eq({ api: nested_namespace })
        expect(namespace.namespaces).to eq({}) # original unchanged
      end
    end
  end

  describe 'listing elements' do
    let(:namespace) do
      described_class.new(
        name: :web,
        tags: { controller: tag_def1, action: tag_def2 },
        metrics: { page_views: metric_def1, request_duration: metric_def2 },
        namespaces: { api: described_class.new(name: :api) }
      )
    end

    describe '#metric_names' do
      it 'returns all metric names' do
        expect(namespace.metric_names).to match_array(%i[page_views request_duration])
      end
    end

    describe '#tag_names' do
      it 'returns all tag names' do
        expect(namespace.tag_names).to match_array(%i[controller action])
      end
    end

    describe '#namespace_names' do
      it 'returns all nested namespace names' do
        expect(namespace.namespace_names).to eq([:api])
      end
    end
  end

  describe 'checking existence' do
    let(:namespace) do
      described_class.new(
        name: :web,
        tags: { controller: tag_def1 },
        metrics: { page_views: metric_def1 },
        namespaces: { api: described_class.new(name: :api) }
      )
    end

    describe '#has_metric?' do
      it 'returns true for existing metrics' do
        expect(namespace.has_metric?(:page_views)).to be true
        expect(namespace.has_metric?('page_views')).to be true
      end

      it 'returns false for non-existing metrics' do
        expect(namespace.has_metric?(:nonexistent)).to be false
      end
    end

    describe '#has_tag?' do
      it 'returns true for existing tags' do
        expect(namespace.has_tag?(:controller)).to be true
        expect(namespace.has_tag?('controller')).to be true
      end

      it 'returns false for non-existing tags' do
        expect(namespace.has_tag?(:nonexistent)).to be false
      end
    end

    describe '#has_namespace?' do
      it 'returns true for existing namespaces' do
        expect(namespace.has_namespace?(:api)).to be true
        expect(namespace.has_namespace?('api')).to be true
      end

      it 'returns false for non-existing namespaces' do
        expect(namespace.has_namespace?(:nonexistent)).to be false
      end
    end
  end

  describe '#all_metrics' do
    let(:api_metric) do
      Datadog::Statsd::Schema::MetricDefinition.new(
        name: :requests,
        type: :counter
      )
    end

    let(:api_namespace) do
      described_class.new(
        name: :api,
        metrics: { requests: api_metric }
      )
    end

    let(:web_namespace) do
      described_class.new(
        name: :web,
        metrics: { page_views: metric_def1 },
        namespaces: { api: api_namespace }
      )
    end

    it 'returns all metrics including from nested namespaces' do
      all_metrics = web_namespace.all_metrics

      expect(all_metrics.keys).to contain_exactly('web.page_views', 'web.api.requests')

      expect(all_metrics['web.page_views'][:definition]).to eq(metric_def1)
      expect(all_metrics['web.page_views'][:namespace_path]).to eq([:web])
      expect(all_metrics['web.page_views'][:namespace]).to eq(web_namespace)

      expect(all_metrics['web.api.requests'][:definition]).to eq(api_metric)
      expect(all_metrics['web.api.requests'][:namespace_path]).to eq(%i[web api])
      expect(all_metrics['web.api.requests'][:namespace]).to eq(api_namespace)
    end

    it 'handles custom parent path' do
      all_metrics = api_namespace.all_metrics(%i[root web])

      expect(all_metrics.keys).to eq(['root.web.api.requests'])
      expect(all_metrics['root.web.api.requests'][:namespace_path]).to eq(%i[root web api])
    end
  end

  describe '#effective_tags' do
    let(:namespace) do
      described_class.new(
        name: :web,
        tags: { controller: tag_def1, action: tag_def2 }
      )
    end

    it 'returns own tags when no parent tags' do
      effective = namespace.effective_tags
      expect(effective).to eq({ controller: tag_def1, action: tag_def2 })
    end

    it 'merges with parent tags' do
      parent_tag = Datadog::Statsd::Schema::TagDefinition.new(name: :region, values: %w[us eu])
      parent_tags = { region: parent_tag }

      effective = namespace.effective_tags(parent_tags)
      expect(effective).to eq({
                                region:     parent_tag,
                                controller: tag_def1,
                                action:     tag_def2
                              })
    end

    it 'prioritizes own tags over parent tags' do
      parent_tag = Datadog::Statsd::Schema::TagDefinition.new(name: :controller, values: %w[different values])
      parent_tags = { controller: parent_tag }

      effective = namespace.effective_tags(parent_tags)
      expect(effective[:controller]).to eq(tag_def1) # own tag wins
    end
  end

  describe '#validate_tag_references' do
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

    let(:namespace) do
      described_class.new(
        name: :web,
        tags: { controller: tag_def1, action: tag_def2 },
        metrics: {
          invalid_metric: invalid_metric,
          valid_metric:   valid_metric
        }
      )
    end

    it 'returns errors for invalid tag references' do
      errors = namespace.validate_tag_references

      expect(errors).to include('Metric invalid_metric references unknown tag: nonexistent_tag')
      expect(errors).to include('Metric invalid_metric requires unknown tag: another_missing_tag')
      expect(errors).not_to include(a_string_matching(/valid_metric/))
    end

    it 'validates nested namespaces recursively' do
      nested_namespace = described_class.new(
        name: :api,
        metrics: { invalid_nested: invalid_metric }
      )

      namespace_with_nested = namespace.add_namespace(nested_namespace)
      errors = namespace_with_nested.validate_tag_references

      expect(errors).to include('Metric invalid_nested references unknown tag: nonexistent_tag')
    end

    it 'returns empty array when all references are valid' do
      valid_namespace = described_class.new(
        name: :web,
        tags: { controller: tag_def1, action: tag_def2 },
        metrics: { valid_metric: valid_metric }
      )

      expect(valid_namespace.validate_tag_references).to eq([])
    end
  end

  describe 'path-based finding' do
    let(:nested_metric) do
      Datadog::Statsd::Schema::MetricDefinition.new(name: :duration, type: :timing)
    end

    let(:deeply_nested_namespace) do
      described_class.new(
        name: :timing,
        metrics: { duration: nested_metric }
      )
    end

    let(:api_namespace) do
      described_class.new(
        name: :api,
        namespaces: { timing: deeply_nested_namespace }
      )
    end

    let(:web_namespace) do
      described_class.new(
        name: :web,
        metrics: { page_views: metric_def1 },
        namespaces: { api: api_namespace }
      )
    end

    describe '#find_metric_by_path' do
      it 'finds metric in current namespace' do
        expect(web_namespace.find_metric_by_path('page_views')).to eq(metric_def1)
      end

      it 'finds metric in nested namespace' do
        expect(web_namespace.find_metric_by_path('api.timing.duration')).to eq(nested_metric)
      end

      it 'returns nil for non-existent paths' do
        expect(web_namespace.find_metric_by_path('nonexistent.path')).to be_nil
        expect(web_namespace.find_metric_by_path('api.nonexistent')).to be_nil
      end
    end

    describe '#find_namespace_by_path' do
      it 'returns self for empty path' do
        expect(web_namespace.find_namespace_by_path('')).to eq(web_namespace)
      end

      it 'finds direct nested namespace' do
        expect(web_namespace.find_namespace_by_path('api')).to eq(api_namespace)
      end

      it 'finds deeply nested namespace' do
        expect(web_namespace.find_namespace_by_path('api.timing')).to eq(deeply_nested_namespace)
      end

      it 'returns nil for non-existent paths' do
        expect(web_namespace.find_namespace_by_path('nonexistent')).to be_nil
        expect(web_namespace.find_namespace_by_path('api.nonexistent')).to be_nil
      end
    end
  end

  describe 'counting methods' do
    let(:deeply_nested_namespace) do
      described_class.new(
        name: :timing,
        metrics: {
          duration: metric_def1,
          latency:  metric_def2
        }
      )
    end

    let(:api_namespace) do
      described_class.new(
        name: :api,
        metrics: { requests: metric_def1 },
        namespaces: { timing: deeply_nested_namespace }
      )
    end

    let(:web_namespace) do
      described_class.new(
        name: :web,
        metrics: { page_views: metric_def1 },
        namespaces: { api: api_namespace }
      )
    end

    describe '#total_metrics_count' do
      it 'counts all metrics including nested' do
        # web: 1 metric + api: 1 metric + timing: 2 metrics = 4 total
        expect(web_namespace.total_metrics_count).to eq(4)
      end

      it 'counts correctly for leaf namespace' do
        expect(deeply_nested_namespace.total_metrics_count).to eq(2)
      end
    end

    describe '#total_namespaces_count' do
      it 'counts all namespaces including nested' do
        # web has 1 direct namespace (api), api has 1 (timing) = 2 total
        expect(web_namespace.total_namespaces_count).to eq(2)
      end

      it 'returns 0 for namespace with no children' do
        expect(deeply_nested_namespace.total_namespaces_count).to eq(0)
      end
    end
  end
end
