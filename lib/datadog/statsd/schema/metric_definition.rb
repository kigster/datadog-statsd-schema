# frozen_string_literal: true

require "dry-struct"
require "dry-types"

module Datadog
  class Statsd
    module Schema
      class MetricDefinition < Dry::Struct
        # Include the types module for easier access
        module Types
          include Dry.Types()
        end

        # Valid metric types in StatsD
        VALID_METRIC_TYPES = %i[counter gauge histogram distribution timing set].freeze

        attribute :name, Types::Strict::Symbol
        attribute :type, Types::Strict::Symbol.constrained(included_in: VALID_METRIC_TYPES)
        attribute :description, Types::String.optional.default(nil)
        attribute :allowed_tags, Types::Array.of(Types::Symbol).default([].freeze)
        attribute :required_tags, Types::Array.of(Types::Symbol).default([].freeze)
        attribute :inherit_tags, Types::String.optional.default(nil)
        attribute :units, Types::String.optional.default(nil)

        # Get the full metric name including namespace path
        def full_name(namespace_path = [])
          return name.to_s if namespace_path.empty?

          "#{namespace_path.join(".")}.#{name}"
        end

        # Check if a tag is allowed for this metric
        def allows_tag?(tag_name)
          tag_symbol = tag_name.to_sym
          allowed_tags.empty? || allowed_tags.include?(tag_symbol)
        end

        # Check if a tag is required for this metric
        def requires_tag?(tag_name)
          tag_symbol = tag_name.to_sym
          required_tags.include?(tag_symbol)
        end

        # Get all missing required tags from a provided tag set
        def missing_required_tags(provided_tags)
          provided_tag_symbols = provided_tags.keys.map(&:to_sym)
          required_tags - provided_tag_symbols
        end

        # Get all invalid tags from a provided tag set
        def invalid_tags(provided_tags)
          return [] if allowed_tags.empty? # No restrictions

          provided_tag_symbols = provided_tags.keys.map(&:to_sym)
          provided_tag_symbols - allowed_tags
        end

        # Validate a complete tag set for this metric
        def valid_tags?(provided_tags)
          missing_required_tags(provided_tags).empty? && invalid_tags(provided_tags).empty?
        end

        # Check if this is a timing-based metric
        def timing_metric?
          %i[timing distribution histogram].include?(type)
        end

        # Check if this is a counting metric
        def counting_metric?
          %i[counter].include?(type)
        end

        # Check if this is a gauge metric
        def gauge_metric?
          type == :gauge
        end

        # Check if this is a set metric
        def set_metric?
          type == :set
        end

        # Get effective tags by merging with inherited tags if present
        def effective_allowed_tags(schema_registry = nil)
          return allowed_tags unless inherit_tags && schema_registry

          inherited_metric = schema_registry.find_metric(inherit_tags)
          return allowed_tags unless inherited_metric

          (inherited_metric.effective_allowed_tags(schema_registry) + allowed_tags).uniq
        end

        def effective_required_tags(schema_registry = nil)
          return required_tags unless inherit_tags && schema_registry

          inherited_metric = schema_registry.find_metric(inherit_tags)
          return required_tags unless inherited_metric

          (inherited_metric.effective_required_tags(schema_registry) + required_tags).uniq
        end
      end
    end
  end
end
