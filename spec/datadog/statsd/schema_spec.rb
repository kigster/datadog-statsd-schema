# frozen_string_literal: true

RSpec.describe Datadog::Statsd::Schema do
  it 'has a version number' do
    expect(Datadog::Statsd::Schema::VERSION).not_to be_nil
  end

  describe '.new' do
    it 'creates a schema using the DSL' do
      schema = described_class.new do
        transformers do
          downcase { |text| text.downcase }
        end

        namespace :web do
          tags do
            tag :controller, values: %w[home users posts]
            tag :action, values: %w[index show create]
          end

          metrics do
            counter :page_views,
                    description: 'Page view counter',
                    tags: { allowed: %w[controller action], required: %w[controller] }
          end
        end
      end

      expect(schema).to be_a(Datadog::Statsd::Schema::Namespace)
      expect(schema.name).to eq(:root)

      web_ns = schema.find_namespace(:web)
      expect(web_ns).not_to be_nil
      expect(web_ns.find_tag(:controller)).not_to be_nil
      expect(web_ns.find_metric(:page_views)).not_to be_nil
    end

    it 'returns an empty schema when no block given' do
      schema = described_class.new

      expect(schema).to be_a(Datadog::Statsd::Schema::Namespace)
      expect(schema.name).to eq(:root)
      expect(schema.namespaces).to be_empty
    end
  end

  describe '.load_file' do
    let(:schema_file_content) do
      <<~RUBY
        transformers do
          downcase { |text| text.downcase }
        end

        namespace :web do
          description 'Web metrics'
        #{'  '}
          tags do
            tag :environment, values: %w[development production]
          end

          metrics do
            counter :requests, tags: { required: %w[environment] }
          end
        end
      RUBY
    end

    it 'loads schema from file content' do
      allow(File).to receive(:read).with('schema.rb').and_return(schema_file_content)

      schema = described_class.load_file('schema.rb')

      expect(schema).to be_a(Datadog::Statsd::Schema::Namespace)
      web_ns = schema.find_namespace(:web)
      expect(web_ns.description).to eq('Web metrics')
      expect(web_ns.find_tag(:environment)).not_to be_nil
      expect(web_ns.find_metric(:requests)).not_to be_nil
    end
  end

  describe '.configure' do
    after do
      # Reset configuration after each test
      described_class.instance_variable_set(:@configuration, nil)
    end

    it 'yields configuration object' do
      mock_statsd = double('statsd')
      mock_schema = double('schema')

      described_class.configure do |config|
        config.statsd = mock_statsd
        config.schema = mock_schema
        config.tags = { env: 'test' }
      end

      config = described_class.configuration
      expect(config.statsd).to eq(mock_statsd)
      expect(config.schema).to eq(mock_schema)
      expect(config.tags).to eq({ env: 'test' })
    end
  end

  describe '.configuration' do
    after do
      # Reset configuration after each test
      described_class.instance_variable_set(:@configuration, nil)
    end

    it 'returns configuration instance' do
      config = described_class.configuration

      expect(config).to be_a(Datadog::Statsd::Schema::Configuration)
      expect(config.statsd).to be_nil
      expect(config.schema).to be_nil
      expect(config.tags).to eq({})
    end

    it 'returns same instance on multiple calls' do
      config1 = described_class.configuration
      config2 = described_class.configuration

      expect(config1).to be(config2)
    end
  end

  describe Datadog::Statsd::Schema::Configuration do
    it 'has default values' do
      config = described_class.new

      expect(config.statsd).to be_nil
      expect(config.schema).to be_nil
      expect(config.tags).to eq({})
    end

    it 'allows setting values' do
      config = described_class.new
      mock_statsd = double('statsd')
      mock_schema = double('schema')

      config.statsd = mock_statsd
      config.schema = mock_schema
      config.tags = { region: 'us-east-1' }

      expect(config.statsd).to eq(mock_statsd)
      expect(config.schema).to eq(mock_schema)
      expect(config.tags).to eq({ region: 'us-east-1' })
    end
  end

  describe 'integration with README example' do
    it 'supports the web performance tracking example from README' do
      schema = described_class.new do
        transformers do
          underscore { |text| text.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '') }
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
              tag :method, values: %i[get post put patch delete head options trace connect], transform: [:downcase]
              tag :status_code, type: :integer, validate: ->(code) { (100..599).include?(code) }
            end

            metrics do
              distribution :duration do
                description 'HTTP request processing time in milliseconds'
                tags allowed: %w[controller action method status_code], required: %w[controller]
              end

              counter :total do
                description 'Total number of requests received'
                tags allowed: %w[controller action method status_code], required: %w[controller]
              end
            end
          end
        end
      end

      # Verify the schema structure matches the README example
      web_ns = schema.find_namespace(:web)
      request_ns = web_ns.find_namespace(:request)

      expect(request_ns).not_to be_nil

      # Check tags
      expect(request_ns.find_tag(:controller)).not_to be_nil
      expect(request_ns.find_tag(:action)).not_to be_nil
      expect(request_ns.find_tag(:method)).not_to be_nil
      expect(request_ns.find_tag(:status_code)).not_to be_nil

      # Check metrics
      duration_metric = request_ns.find_metric(:duration)
      expect(duration_metric.type).to eq(:distribution)
      expect(duration_metric.description).to eq('HTTP request processing time in milliseconds')
      expect(duration_metric.required_tags).to eq([:controller])

      total_metric = request_ns.find_metric(:total)
      expect(total_metric.type).to eq(:counter)
      expect(total_metric.description).to eq('Total number of requests received')
      expect(total_metric.required_tags).to eq([:controller])

      # Verify tag validation works
      controller_tag = request_ns.find_tag(:controller)
      expect(controller_tag.allows_value?('home_controller')).to be true
      expect(controller_tag.allows_value?('HomeController')).to be true # should be transformed

      status_code_tag = request_ns.find_tag(:status_code)
      expect(status_code_tag.valid_value?(200)).to be true
      expect(status_code_tag.valid_value?(999)).to be false
    end
  end
end
