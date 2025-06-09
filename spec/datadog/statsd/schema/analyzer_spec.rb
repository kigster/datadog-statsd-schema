# frozen_string_literal: true

require "spec_helper"

RSpec.describe Datadog::Statsd::Schema::Analyzer do
  describe "#analyze" do
    let(:schema) do
      Datadog::Statsd::Schema.new do
        namespace :web do
          tags do
            tag :environment, values: %w[production staging development]  # 3 values
            tag :service, values: %w[api web]                             # 2 values
            tag :region, values: %w[us eu]                                # 2 values
          end

          namespace :requests do
            metrics do
              counter :total do
                description "Total requests"
                tags required: [:environment], allowed: [:service] # 2 tags: env (3) * service (2) = 6 combinations
              end

              distribution :response_time do
                description "Response time"
                inherit_tags "web.requests.total"
                tags required: %i[region] # 3 tags: env (3) * service (2) * region (2) = 12 combinations, 10 expansions = 120
              end
            end
          end

          metrics do
            gauge :memory_usage do
              description "Memory usage"
              inherit_tags "web.requests.total"
              tags allowed: %i[region] # 2 tags: env (3) * region (2) = 6 combinations, 5 expansions = 30
            end
          end

          namespace :cache do
            tags do
              tag :cache_type, values: %w[redis memcached] # 2 values
            end

            metrics do
              histogram :hit_duration do
                description "Cache hit duration"
                inherit_tags "web.requests.total"
                tags required: [:cache_type] # 1 tag: cache_type (2) = 2 combinations, 10 expansions = 20
              end
            end
          end
        end
      end
    end

    let(:stdout) { StringIO.new }
    let(:stderr) { StringIO.new }
    let(:analyzer) { described_class.new([schema], stdout: stdout, stderr: stderr, format: :text) }

    it "calculates correct analysis results" do
      result = analyzer.analyze

      expect(result).to be_a(Datadog::Statsd::Schema::AnalysisResult)
      expect(result.metrics_analysis.size).to eq(4)

      # Test counter metric (no expansion) - web.requests.total
      requests_metric = result.metrics_analysis.find { |m| m[:metric_name] == "web.requests.total" }
      expect(requests_metric[:metric_type]).to eq(:counter)
      expect(requests_metric[:expanded_names]).to eq(["web.requests.total"])
      expect(requests_metric[:unique_tags]).to eq(2) # environment, service
      expect(requests_metric[:unique_tag_values]).to eq(5) # 3 env + 2 service
      expect(requests_metric[:total_combinations]).to eq(6) # 3 * 2 * 1 expansion

      # Test gauge metric (5 expansions) - web.memory_usage
      # Inherits from web.requests.total (env + service) + allows region
      memory_metric = result.metrics_analysis.find { |m| m[:metric_name] == "web.memory_usage" }
      expect(memory_metric[:metric_type]).to eq(:gauge)
      expect(memory_metric[:expanded_names].size).to eq(5) # count, min, max, sum, avg
      expect(memory_metric[:unique_tags]).to eq(3) # environment, service (inherited), region (allowed)
      expect(memory_metric[:unique_tag_values]).to eq(7) # 3 env + 2 service + 2 region
      expect(memory_metric[:total_combinations]).to eq(60) # 3 * 2 * 2 * 5 expansions

      # Test distribution metric (10 expansions) - web.requests.response_time
      # Inherits from web.requests.total (env + service) + requires region
      response_metric = result.metrics_analysis.find { |m| m[:metric_name] == "web.requests.response_time" }
      expect(response_metric[:metric_type]).to eq(:distribution)
      expect(response_metric[:expanded_names].size).to eq(10) # count, min, max, sum, avg, p50, p75, p90, p95, p99
      expect(response_metric[:unique_tags]).to eq(3) # environment, service (inherited), region (required)
      expect(response_metric[:unique_tag_values]).to eq(7) # 3 env + 2 service + 2 region
      expect(response_metric[:total_combinations]).to eq(120) # 3 * 2 * 2 * 10 expansions

      # Test histogram metric (10 expansions) - web.cache.hit_duration
      # Inherits from web.requests.total (env + service) + requires cache_type
      cache_metric = result.metrics_analysis.find { |m| m[:metric_name] == "web.cache.hit_duration" }
      expect(cache_metric[:metric_type]).to eq(:histogram)
      expect(cache_metric[:expanded_names].size).to eq(5)
      expect(cache_metric[:unique_tags]).to eq(3) # environment, service (inherited), cache_type (required)
      expect(cache_metric[:unique_tag_values]).to eq(7) # 3 env + 2 service + 2 cache_type
      expect(cache_metric[:total_combinations]).to eq(60) # 3 * 2 * 2 * 50 expansions

      # Test totals
      expect(result.total_unique_metrics).to eq(21)
      expect(result.total_possible_custom_metrics).to eq(246) # 6 + 60 + 120 + 120
    end

    it "handles schemas with no metrics" do
      empty_schema = Datadog::Statsd::Schema.new do
        namespace :empty do
          tags do
            tag :env, values: %w[test]
          end
        end
      end

      analyzer = described_class.new([empty_schema], stdout: stdout, stderr: stderr)
      result = analyzer.analyze

      expect(result.total_unique_metrics).to eq(0)
      expect(result.total_possible_custom_metrics).to eq(0)
      expect(result.metrics_analysis).to be_empty
    end

    it "handles multiple schemas" do
      schema1 = Datadog::Statsd::Schema.new do
        namespace :app1 do
          tags do
            tag :env, values: %w[prod dev]
          end
          metrics do
            counter :requests do
              tags required: [:env]
            end
          end
        end
      end

      schema2 = Datadog::Statsd::Schema.new do
        namespace :app2 do
          tags do
            tag :service, values: %w[api web]
          end
          metrics do
            gauge :memory do
              tags required: [:service]
            end
          end
        end
      end

      analyzer = described_class.new([schema1, schema2], stdout: stdout, stderr: stderr)
      result = analyzer.analyze

      expect(result.metrics_analysis.size).to eq(2)
      expect(result.total_unique_metrics).to eq(6) # 1 counter + 5 gauge expansions
      expect(result.total_possible_custom_metrics).to eq(12) # 2 (counter) + 10 (gauge: 2 * 5)
    end
  end

  describe "metric expansion constants" do
    it "defines correct expansions for each metric type" do
      expect(described_class::METRIC_EXPANSIONS[:gauge]).to eq(%w[count min max sum avg])
      expect(described_class::METRIC_EXPANSIONS[:distribution]).to eq(%w[count min max sum avg p50 p75 p90 p95 p99])
      expect(described_class::METRIC_EXPANSIONS[:histogram]).to eq(%w[count min max sum avg])
    end
  end
end
