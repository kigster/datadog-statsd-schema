# frozen_string_literal: true

require "dry-struct"
require "dry-types"
require_relative "tag_definition"
require_relative "metric_definition"

# @author Datadog Team
# @since 0.1.0
module Datadog
  class Statsd
    # Schema definition and validation module for StatsD metrics
    module Schema
      # Represents a namespace in the metric schema hierarchy
      # Namespaces contain tags, metrics, and nested namespaces, providing organization and scoping
      # @example Basic namespace
      #   namespace = Namespace.new(
      #     name: :web,
      #     description: "Web application metrics"
      #   )
      # @example Namespace with tags and metrics
      #   namespace = Namespace.new(
      #     name: :api,
      #     tags: { controller: tag_def, action: tag_def2 },
      #     metrics: { requests: metric_def }
      #   )
      # @author Datadog Team
      # @since 0.1.0
      class Namespace < Dry::Struct
        # Include the types module for easier access to Dry::Typesa
        module Types
          include Dry.Types()
        end

        # The namespace name as a symbol
        # @return [Symbol] Namespace name
        attribute :name, Types::Strict::Symbol

        # Hash of tag definitions within this namespace
        # @return [Hash<Symbol, TagDefinition>] Tag name to TagDefinition mapping
        attribute :tags, Types::Hash.map(Types::Symbol, TagDefinition).default({}.freeze)

        # Hash of metric definitions within this namespace
        # @return [Hash<Symbol, MetricDefinition>] Metric name to MetricDefinition mapping
        attribute :metrics, Types::Hash.map(Types::Symbol, MetricDefinition).default({}.freeze)

        # Hash of nested namespaces within this namespace
        # @return [Hash<Symbol, Namespace>] Namespace name to Namespace mapping
        attribute :namespaces, Types::Hash.map(Types::Symbol, Namespace).default({}.freeze)

        # Human-readable description of this namespace
        # @return [String, nil] Description text
        attribute :description, Types::String.optional.default(nil)

        # Get the full path of this namespace including parent namespaces
        # @param parent_path [Array<Symbol>] Array of parent namespace names
        # @return [Array<Symbol>] Full namespace path
        # @example
        #   namespace.full_path([:web, :api])  # => [:web, :api, :request]
        def full_path(parent_path = [])
          return [name] if parent_path.empty?

          parent_path + [name]
        end

        # Find a metric by name within this namespace
        # @param metric_name [String, Symbol] Name of the metric to find
        # @return [MetricDefinition, nil] The metric definition or nil if not found
        # @example
        #   namespace.find_metric(:page_views)  # => MetricDefinition instance
        def find_metric(metric_name)
          metric_symbol = metric_name.to_sym
          metrics[metric_symbol]
        end

        # Find a tag definition by name within this namespace
        # @param tag_name [String, Symbol] Name of the tag to find
        # @return [TagDefinition, nil] The tag definition or nil if not found
        # @example
        #   namespace.find_tag(:controller)  # => TagDefinition instance
        def find_tag(tag_name)
          tag_symbol = tag_name.to_sym
          tags[tag_symbol]
        end

        # Find a nested namespace by name
        # @param namespace_name [String, Symbol] Name of the namespace to find
        # @return [Namespace, nil] The nested namespace or nil if not found
        # @example
        #   namespace.find_namespace(:api)  # => Namespace instance
        def find_namespace(namespace_name)
          namespace_symbol = namespace_name.to_sym
          namespaces[namespace_symbol]
        end

        # Add a new metric to this namespace (returns new namespace instance)
        # @param metric_definition [MetricDefinition] The metric definition to add
        # @return [Namespace] New namespace instance with the added metric
        def add_metric(metric_definition)
          new(metrics: metrics.merge(metric_definition.name => metric_definition))
        end

        # Add a new tag definition to this namespace (returns new namespace instance)
        # @param tag_definition [TagDefinition] The tag definition to add
        # @return [Namespace] New namespace instance with the added tag
        def add_tag(tag_definition)
          new(tags: tags.merge(tag_definition.name => tag_definition))
        end

        # Add a nested namespace (returns new namespace instance)
        # @param namespace [Namespace] The namespace to add
        # @return [Namespace] New namespace instance with the added namespace
        def add_namespace(namespace)
          new(namespaces: namespaces.merge(namespace.name => namespace))
        end

        # Get all metric names in this namespace (not including nested)
        # @return [Array<Symbol>] Array of metric names
        def metric_names
          metrics.keys
        end

        # Get all tag names in this namespace
        # @return [Array<Symbol>] Array of tag names
        def tag_names
          tags.keys
        end

        # Get all nested namespace names
        # @return [Array<Symbol>] Array of namespace names
        def namespace_names
          namespaces.keys
        end

        # Check if this namespace contains a metric
        # @param metric_name [String, Symbol] Name of the metric to check
        # @return [Boolean] true if metric exists
        def has_metric?(metric_name)
          metric_symbol = metric_name.to_sym
          metrics.key?(metric_symbol)
        end

        # Check if this namespace contains a tag definition
        # @param tag_name [String, Symbol] Name of the tag to check
        # @return [Boolean] true if tag exists
        def has_tag?(tag_name)
          tag_symbol = tag_name.to_sym
          tags.key?(tag_symbol)
        end

        # Check if this namespace contains a nested namespace
        # @param namespace_name [String, Symbol] Name of the namespace to check
        # @return [Boolean] true if namespace exists
        def has_namespace?(namespace_name)
          namespace_symbol = namespace_name.to_sym
          namespaces.key?(namespace_symbol)
        end

        # Get all metrics recursively including from nested namespaces
        # @param path [Array<Symbol>] Current namespace path (used for recursion)
        # @return [Hash] Hash mapping full metric names to metric info
        # @example
        #   {
        #     "web.page_views" => {
        #       definition: MetricDefinition,
        #       namespace_path: [:web],
        #       namespace: Namespace
        #     }
        #   }
        def all_metrics(path = [])
          # Filter out :root from the path to avoid it appearing in metric names
          current_path = path + [name]
          filtered_path = current_path.reject { |part| part == :root }
          result = {}

          # Add metrics from this namespace
          metrics.each do |_metric_name, metric_def|
            full_metric_name = metric_def.full_name(filtered_path)
            result[full_metric_name] = {
              definition: metric_def,
              namespace_path: filtered_path,
              namespace: self
            }
          end

          # Add metrics from nested namespaces recursively
          namespaces.each do |_, nested_namespace|
            result.merge!(nested_namespace.all_metrics(current_path))
          end

          result
        end

        # Get all tag definitions including inherited from parent namespaces
        # @param parent_tags [Hash] Tag definitions from parent namespaces
        # @return [Hash<Symbol, TagDefinition>] Combined tag definitions
        def effective_tags(parent_tags = {})
          parent_tags.merge(tags)
        end

        # Validate that all tag references in metrics exist
        # @return [Array<String>] Array of validation error messages
        def validate_tag_references
          errors = []

          metrics.each do |metric_name, metric_def|
            # Check allowed tags
            metric_def.allowed_tags.each do |tag_name|
              errors << "Metric #{metric_name} references unknown tag: #{tag_name}" unless has_tag?(tag_name)
            end

            # Check required tags
            metric_def.required_tags.each do |tag_name|
              errors << "Metric #{metric_name} requires unknown tag: #{tag_name}" unless has_tag?(tag_name)
            end
          end

          # Validate nested namespaces recursively
          namespaces.each do |_, nested_namespace|
            errors.concat(nested_namespace.validate_tag_references)
          end

          errors
        end

        # Find metric by path (e.g., "request.duration" within web namespace)
        # @param path [String] Dot-separated path to the metric
        # @return [MetricDefinition, nil] The metric definition or nil if not found
        # @example
        #   namespace.find_metric_by_path("api.requests")  # => MetricDefinition
        def find_metric_by_path(path)
          parts = path.split(".")

          if parts.length == 1
            # Single part, look for metric in this namespace
            find_metric(parts.first)
          else
            # Multiple parts, navigate to nested namespace
            namespace_name = parts.first
            remaining_path = parts[1..-1].join(".")

            nested_namespace = find_namespace(namespace_name)
            return nil unless nested_namespace

            nested_namespace.find_metric_by_path(remaining_path)
          end
        end

        # Get namespace by path (e.g., "web.request")
        # @param path [String] Dot-separated path to the namespace
        # @return [Namespace, nil] The namespace or nil if not found
        # @example
        #   root_namespace.find_namespace_by_path("web.api")  # => Namespace
        def find_namespace_by_path(path)
          return self if path.empty?

          parts = path.split(".")

          if parts.length == 1
            find_namespace(parts.first)
          else
            namespace_name = parts.first
            remaining_path = parts[1..-1].join(".")

            nested_namespace = find_namespace(namespace_name)
            return nil unless nested_namespace

            nested_namespace.find_namespace_by_path(remaining_path)
          end
        end

        # Count total metrics including nested namespaces
        # @return [Integer] Total number of metrics in this namespace tree
        def total_metrics_count
          metrics.count + namespaces.values.sum(&:total_metrics_count)
        end

        # Count total namespaces including nested
        # @return [Integer] Total number of namespaces in this namespace tree
        def total_namespaces_count
          namespaces.count + namespaces.values.sum(&:total_namespaces_count)
        end
      end
    end
  end
end
