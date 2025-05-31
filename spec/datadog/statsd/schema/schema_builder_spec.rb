# frozen_string_literal: true

RSpec.describe Datadog::Statsd::Schema::SchemaBuilder do
  describe 'initialization' do
    it 'creates a builder with empty transformers and root namespace' do
      builder = described_class.new

      expect(builder.transformers).to eq({})
      expect(builder.root_namespace.name).to eq(:root)
      expect(builder.root_namespace.namespaces).to eq({})
    end
  end

  describe '#transformers' do
    it 'defines transformers using DSL' do
      builder = described_class.new

      builder.transformers do
        underscore { |text| text.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '') }
        downcase { |text| text.downcase }
      end

      expect(builder.transformers[:underscore]).to be_a(Proc)
      expect(builder.transformers[:downcase]).to be_a(Proc)
      expect(builder.transformers[:underscore].call('HomeController')).to eq('home_controller')
      expect(builder.transformers[:downcase].call('HELLO')).to eq('hello')
    end

    it 'accepts lambda syntax' do
      builder = described_class.new
      downcase_proc = ->(text) { text.downcase }

      builder.transformers do
        downcase downcase_proc
      end

      expect(builder.transformers[:downcase]).to eq(downcase_proc)
    end
  end

  describe '#namespace' do
    it 'adds namespace to root' do
      builder = described_class.new

      builder.namespace :web do
        description 'Web application metrics'
      end

      web_namespace = builder.root_namespace.find_namespace(:web)
      expect(web_namespace).not_to be_nil
      expect(web_namespace.name).to eq(:web)
      expect(web_namespace.description).to eq('Web application metrics')
    end

    it 'supports nested namespaces' do
      builder = described_class.new

      builder.namespace :web do
        namespace :api do
          description 'API metrics'
        end
      end

      web_namespace = builder.root_namespace.find_namespace(:web)
      api_namespace = web_namespace.find_namespace(:api)

      expect(api_namespace).not_to be_nil
      expect(api_namespace.name).to eq(:api)
      expect(api_namespace.description).to eq('API metrics')
    end
  end

  describe 'complete schema definition' do
    let(:schema) do
      described_class.new.tap do |builder|
        builder.transformers do
          underscore { |text| text.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '') }
          downcase { |text| text.downcase }
        end

        builder.namespace :web do
          description 'Web application metrics'

          tags do
            tag :controller, values: %w[home users posts], transform: %i[underscore downcase]
            tag :action, values: %w[index show create update destroy]
            tag :method, values: %i[get post put patch delete], type: :symbol
            tag :status_code, type: :integer, validate: ->(code) { (100..599).include?(code.to_i) }
          end

          metrics do
            counter :page_views,
                    description: 'Number of page views',
                    tags: { allowed: %w[controller action method], required: %w[controller] }

            distribution :request_duration,
                         description: 'Request processing time',
                         units: 'milliseconds',
                         tags: { allowed: %w[controller action method status_code], required: %w[controller] }

            namespace :api do
              counter :requests,
                      description: 'API requests count',
                      inherit_tags: 'web.page_views'
            end
          end

          namespace :database do
            tags do
              tag :table, values: %w[users posts comments]
              tag :operation, values: %w[select insert update delete]
            end

            metrics do
              histogram :query_duration,
                        description: 'Database query time',
                        tags: { allowed: %w[table operation], required: %w[table] }
            end
          end
        end
      end.build
    end

    it 'creates a complete schema structure' do
      # Root namespace
      expect(schema.name).to eq(:root)
      expect(schema.namespaces.keys).to eq([:web])

      # Web namespace
      web_ns = schema.find_namespace(:web)
      expect(web_ns.description).to eq('Web application metrics')
      expect(web_ns.tag_names).to match_array(%i[controller action method status_code])
      expect(web_ns.metric_names).to match_array(%i[page_views request_duration api_requests])
      expect(web_ns.namespace_names).to eq([:database])

      # Web tags
      controller_tag = web_ns.find_tag(:controller)
      expect(controller_tag.values).to eq(%w[home users posts])
      expect(controller_tag.transform).to eq(%i[underscore downcase])

      status_tag = web_ns.find_tag(:status_code)
      expect(status_tag.type).to eq(:integer)
      expect(status_tag.validate).to be_a(Proc)

      # Web metrics
      page_views = web_ns.find_metric(:page_views)
      expect(page_views.type).to eq(:counter)
      expect(page_views.description).to eq('Number of page views')
      expect(page_views.allowed_tags).to match_array(%i[controller action method])
      expect(page_views.required_tags).to eq([:controller])

      request_duration = web_ns.find_metric(:request_duration)
      expect(request_duration.type).to eq(:distribution)
      expect(request_duration.units).to eq('milliseconds')
      expect(request_duration.allowed_tags).to match_array(%i[controller action method status_code])

      api_requests = web_ns.find_metric(:api_requests)
      expect(api_requests.type).to eq(:counter)
      expect(api_requests.inherit_tags).to eq('web.page_views')

      # Database namespace
      db_ns = web_ns.find_namespace(:database)
      expect(db_ns.tag_names).to match_array(%i[table operation])
      expect(db_ns.metric_names).to eq([:query_duration])

      # Database tags
      table_tag = db_ns.find_tag(:table)
      expect(table_tag.values).to eq(%w[users posts comments])

      # Database metrics
      query_duration = db_ns.find_metric(:query_duration)
      expect(query_duration.type).to eq(:histogram)
      expect(query_duration.allowed_tags).to match_array(%i[table operation])
      expect(query_duration.required_tags).to eq([:table])
    end

    it 'creates metrics with correct full names' do
      all_metrics = schema.find_namespace(:web).all_metrics

      expect(all_metrics.keys).to include('web.page_views')
      expect(all_metrics.keys).to include('web.request_duration')
      expect(all_metrics.keys).to include('web.api_requests')
      expect(all_metrics.keys).to include('web.database.query_duration')
    end
  end

  describe '#validate!' do
    it 'passes validation for valid schema' do
      builder = described_class.new

      builder.namespace :web do
        tags do
          tag :controller, values: %w[home users]
        end

        metrics do
          counter :page_views, tags: { required: %w[controller] }
        end
      end

      expect { builder.validate! }.not_to raise_error
    end

    it 'raises error for invalid tag references' do
      builder = described_class.new

      builder.namespace :web do
        tags do
          tag :controller, values: %w[home users]
        end

        metrics do
          counter :page_views, tags: { required: %w[nonexistent_tag] }
        end
      end

      expect { builder.validate! }.to raise_error(
        Datadog::Statsd::Schema::SchemaError,
        /Schema validation failed.*nonexistent_tag/
      )
    end
  end

  describe 'metric block syntax' do
    it 'supports defining metrics with blocks' do
      builder = described_class.new

      builder.namespace :web do
        tags do
          tag :controller, values: %w[home users]
          tag :action, values: %w[index show]
        end

        metrics do
          distribution :request_duration do
            description 'HTTP request processing time'
            tags allowed: %w[controller action], required: %w[controller]
            units 'milliseconds'
            inherit_tags 'web.base_metric'
          end
        end
      end

      schema = builder.build
      metric = schema.find_namespace(:web).find_metric(:request_duration)

      expect(metric.description).to eq('HTTP request processing time')
      expect(metric.allowed_tags).to match_array(%i[controller action])
      expect(metric.required_tags).to eq([:controller])
      expect(metric.units).to eq('milliseconds')
      expect(metric.inherit_tags).to eq('web.base_metric')
    end
  end

  describe 'all metric types' do
    it 'supports all StatsD metric types' do
      builder = described_class.new

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

      schema = builder.build
      test_ns = schema.find_namespace(:test)

      expect(test_ns.find_metric(:page_views).type).to eq(:counter)
      expect(test_ns.find_metric(:memory_usage).type).to eq(:gauge)
      expect(test_ns.find_metric(:response_time).type).to eq(:histogram)
      expect(test_ns.find_metric(:latency).type).to eq(:distribution)
      expect(test_ns.find_metric(:duration).type).to eq(:timing)
      expect(test_ns.find_metric(:unique_users).type).to eq(:set)
    end
  end

  describe 'nested metrics namespaces' do
    it 'handles metrics with nested namespace syntax' do
      builder = described_class.new

      builder.namespace :web do
        metrics do
          namespace :request do
            counter :total
            distribution :duration
          end

          counter :page_views
        end
      end

      schema = builder.build
      web_ns = schema.find_namespace(:web)

      # Check that nested namespace metrics get prefixed names
      expect(web_ns.metric_names).to include(:request_total)
      expect(web_ns.metric_names).to include(:request_duration)
      expect(web_ns.metric_names).to include(:page_views)

      expect(web_ns.find_metric(:request_total).type).to eq(:counter)
      expect(web_ns.find_metric(:request_duration).type).to eq(:distribution)
    end
  end
end
