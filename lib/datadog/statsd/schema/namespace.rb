# frozen_string_literal: true

require 'dry-struct'
require 'dry-types'
require_relative 'tag_definition'
require_relative 'metric_definition'

module Datadog
  class Statsd
    module Schema
      class Namespace < Dry::Struct
        # Include the types module for easier access
        module Types
          include Dry.Types()
        end

        attribute :name, Types::Strict::Symbol
        attribute :tags, Types::Hash.map(Types::Symbol, TagDefinition).default({}.freeze)
        attribute :metrics, Types::Hash.map(Types::Symbol, MetricDefinition).default({}.freeze)
        attribute :namespaces, Types::Hash.map(Types::Symbol, Namespace).default({}.freeze)
        attribute :description, Types::String.optional.default(nil)

        # Get the full path of this namespace
        def full_path(parent_path = [])
          return [name] if parent_path.empty?

          parent_path + [name]
        end

        # Find a metric by name within this namespace
        def find_metric(metric_name)
          metric_symbol = metric_name.to_sym
          metrics[metric_symbol]
        end

        # Find a tag definition by name within this namespace
        def find_tag(tag_name)
          tag_symbol = tag_name.to_sym
          tags[tag_symbol]
        end

        # Find a nested namespace by name
        def find_namespace(namespace_name)
          namespace_symbol = namespace_name.to_sym
          namespaces[namespace_symbol]
        end

        # Add a new metric to this namespace
        def add_metric(metric_definition)
          new(metrics: metrics.merge(metric_definition.name => metric_definition))
        end

        # Add a new tag definition to this namespace
        def add_tag(tag_definition)
          new(tags: tags.merge(tag_definition.name => tag_definition))
        end

        # Add a nested namespace
        def add_namespace(namespace)
          new(namespaces: namespaces.merge(namespace.name => namespace))
        end

        # Get all metric names in this namespace (not including nested)
        def metric_names
          metrics.keys
        end

        # Get all tag names in this namespace
        def tag_names
          tags.keys
        end

        # Get all nested namespace names
        def namespace_names
          namespaces.keys
        end

        # Check if this namespace contains a metric
        def has_metric?(metric_name)
          metric_symbol = metric_name.to_sym
          metrics.key?(metric_symbol)
        end

        # Check if this namespace contains a tag definition
        def has_tag?(tag_name)
          tag_symbol = tag_name.to_sym
          tags.key?(tag_symbol)
        end

        # Check if this namespace contains a nested namespace
        def has_namespace?(namespace_name)
          namespace_symbol = namespace_name.to_sym
          namespaces.key?(namespace_symbol)
        end

        # Get all metrics recursively including from nested namespaces
        def all_metrics(path = [])
          current_path = path + [name]
          result = {}

          # Add metrics from this namespace
          metrics.each do |_metric_name, metric_def|
            full_metric_name = metric_def.full_name(current_path)
            result[full_metric_name] = {
              definition:     metric_def,
              namespace_path: current_path,
              namespace:      self
            }
          end

          # Add metrics from nested namespaces recursively
          namespaces.each do |_, nested_namespace|
            result.merge!(nested_namespace.all_metrics(current_path))
          end

          result
        end

        # Get all tag definitions including inherited from parent namespaces
        def effective_tags(parent_tags = {})
          parent_tags.merge(tags)
        end

        # Validate that all tag references in metrics exist
        def validate_tag_references
          errors = []

          metrics.each do |metric_name, metric_def|
            # Check allowed tags
            metric_def.allowed_tags.each do |tag_name|
              unless has_tag?(tag_name)
                errors << "Metric #{metric_name} references unknown tag: #{tag_name}"
              end
            end

            # Check required tags
            metric_def.required_tags.each do |tag_name|
              unless has_tag?(tag_name)
                errors << "Metric #{metric_name} requires unknown tag: #{tag_name}"
              end
            end
          end

          # Validate nested namespaces recursively
          namespaces.each do |_, nested_namespace|
            errors.concat(nested_namespace.validate_tag_references)
          end

          errors
        end

        # Find metric by path (e.g., "request.duration" within web namespace)
        def find_metric_by_path(path)
          parts = path.split('.')

          if parts.length == 1
            # Single part, look for metric in this namespace
            find_metric(parts.first)
          else
            # Multiple parts, navigate to nested namespace
            namespace_name = parts.first
            remaining_path = parts[1..-1].join('.')

            nested_namespace = find_namespace(namespace_name)
            return nil unless nested_namespace

            nested_namespace.find_metric_by_path(remaining_path)
          end
        end

        # Get namespace by path (e.g., "web.request")
        def find_namespace_by_path(path)
          return self if path.empty?

          parts = path.split('.')

          if parts.length == 1
            find_namespace(parts.first)
          else
            namespace_name = parts.first
            remaining_path = parts[1..-1].join('.')

            nested_namespace = find_namespace(namespace_name)
            return nil unless nested_namespace

            nested_namespace.find_namespace_by_path(remaining_path)
          end
        end

        # Count total metrics including nested namespaces
        def total_metrics_count
          metrics.count + namespaces.values.sum(&:total_metrics_count)
        end

        # Count total namespaces including nested
        def total_namespaces_count
          namespaces.count + namespaces.values.sum(&:total_namespaces_count)
        end
      end
    end
  end
end
