# frozen_string_literal: true

require "dry-struct"
require "dry-types"

# @author Datadog Team
# @since 0.1.0
module Datadog
  class Statsd
    # Schema definition and validation module for StatsD metrics
    module Schema
      # Represents a metric definition within a schema namespace
      # Defines the metric type, allowed/required tags, validation rules, and metadata
      # @example Basic metric definition
      #   metric_def = MetricDefinition.new(
      #     name: :page_views,
      #     type: :counter,
      #     allowed_tags: [:controller, :action],
      #     required_tags: [:controller]
      #   )
      # @example Metric with description and units
      #   metric_def = MetricDefinition.new(
      #     name: :request_duration,
      #     type: :distribution,
      #     description: "HTTP request processing time",
      #     units: "milliseconds",
      #     allowed_tags: [:controller, :action, :status_code],
      #     required_tags: [:controller, :action]
      #   )
      # @author Datadog Team
      # @since 0.1.0
      class MetricDefinition < Dry::Struct
        # Include the types module for easier access to Dry::Types
        module Types
          include Dry.Types()
        end

        # Valid metric types supported by StatsD
        VALID_METRIC_TYPES = %i[counter gauge histogram distribution timing set].freeze

        # The metric name as a symbol
        # @return [Symbol] Metric name
        attribute :name, Types::Strict::Symbol

        # The metric type (counter, gauge, histogram, distribution, timing, set)
        # @return [Symbol] One of the valid metric types
        attribute :type, Types::Strict::Symbol.constrained(included_in: VALID_METRIC_TYPES)

        # Human-readable description of what this metric measures
        # @return [String, nil] Description text
        attribute :description, Types::String.optional.default(nil)

        # Array of tag names that are allowed for this metric
        # @return [Array<Symbol>] Allowed tag names (empty array means all tags allowed)
        attribute :allowed_tags, Types::Array.of(Types::Symbol).default([].freeze)

        # Array of tag names that are required for this metric
        # @return [Array<Symbol>] Required tag names
        attribute :required_tags, Types::Array.of(Types::Symbol).default([].freeze)

        # Path to another metric to inherit tags from
        # @return [String, nil] Dot-separated path to parent metric
        attribute :inherit_tags, Types::String.optional.default(nil)

        # Units of measurement for this metric (e.g., "milliseconds", "bytes")
        # @return [String, nil] Unit description
        attribute :units, Types::String.optional.default(nil)

        # The namespace this metric belongs to
        # @return [Symbol, nil] Namespace name
        attribute :namespace, Types::Strict::Symbol.optional.default(nil)

        # Get the full metric name including namespace path
        # @param namespace_path [Array<Symbol>] Array of namespace names leading to this metric
        # @return [String] Fully qualified metric name
        # @example
        #   metric_def.full_name([:web, :api])  # => "web.api.page_views"
        def full_name(namespace_path = [])
          return name.to_s if namespace_path.empty?

          "#{namespace_path.join(".")}.#{name}"
        end

        # Check if a tag is allowed for this metric
        # @param tag_name [String, Symbol] Tag name to check
        # @return [Boolean] true if tag is allowed (or no restrictions exist)
        # @example
        #   metric_def.allows_tag?(:controller)  # => true
        #   metric_def.allows_tag?(:invalid_tag) # => false (if restrictions exist)
        def allows_tag?(tag_name)
          tag_symbol = tag_name.to_sym
          allowed_tags.empty? || allowed_tags.include?(tag_symbol)
        end

        # Check if a tag is required for this metric
        # @param tag_name [String, Symbol] Tag name to check
        # @return [Boolean] true if tag is required
        # @example
        #   metric_def.requires_tag?(:controller)  # => true
        #   metric_def.requires_tag?(:optional_tag) # => false
        def requires_tag?(tag_name)
          tag_symbol = tag_name.to_sym
          required_tags.include?(tag_symbol)
        end

        # Get all missing required tags from a provided tag set
        # @param provided_tags [Hash] Hash of tag names to values
        # @return [Array<Symbol>] Array of missing required tag names
        # @example
        #   metric_def.missing_required_tags(controller: "users")
        #   # => [:action] (if action is also required)
        def missing_required_tags(provided_tags)
          provided_tag_symbols = provided_tags.keys.map(&:to_sym)
          required_tags - provided_tag_symbols
        end

        # Get all invalid tags from a provided tag set
        # @param provided_tags [Hash] Hash of tag names to values
        # @return [Array<Symbol>] Array of invalid tag names
        # @example
        #   metric_def.invalid_tags(controller: "users", invalid: "value")
        #   # => [:invalid] (if only controller is allowed)
        def invalid_tags(provided_tags)
          return [] if allowed_tags.empty? # No restrictions

          provided_tag_symbols = provided_tags.keys.map(&:to_sym)
          provided_tag_symbols - allowed_tags
        end

        # Validate a complete tag set for this metric
        # @param provided_tags [Hash] Hash of tag names to values
        # @return [Boolean] true if all tags are valid
        # @example
        #   metric_def.valid_tags?(controller: "users", action: "show")  # => true
        def valid_tags?(provided_tags)
          missing_required_tags(provided_tags).empty? && invalid_tags(provided_tags).empty?
        end

        # Check if this is a timing-based metric
        # @return [Boolean] true for timing, distribution, or histogram metrics
        def timing_metric?
          %i[timing distribution histogram].include?(type)
        end

        # Check if this is a counting metric
        # @return [Boolean] true for counter metrics
        def counting_metric?
          %i[counter].include?(type)
        end

        # Check if this is a gauge metric
        # @return [Boolean] true for gauge metrics
        def gauge_metric?
          type == :gauge
        end

        # Check if this is a set metric
        # @return [Boolean] true for set metrics
        def set_metric?
          type == :set
        end

        # Get effective allowed tags by merging with inherited tags if present
        # @param schema_registry [Object] Registry to look up inherited metrics
        # @return [Array<Symbol>] Combined allowed tags including inherited ones
        def effective_allowed_tags(schema_registry = nil)
          return allowed_tags unless inherit_tags && schema_registry

          inherited_metric = schema_registry.find_metric(inherit_tags)
          return allowed_tags unless inherited_metric

          (inherited_metric.effective_allowed_tags(schema_registry) + allowed_tags).uniq
        end

        # Get effective required tags by merging with inherited tags if present
        # @param schema_registry [Object] Registry to look up inherited metrics
        # @return [Array<Symbol>] Combined required tags including inherited ones
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
