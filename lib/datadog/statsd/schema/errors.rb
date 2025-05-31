# frozen_string_literal: true

module Datadog
  class Statsd
    module Schema
      class SchemaError < Error; end

      class UnknownMetricError < SchemaError
        def initialize(namespace, metric_name)
          super(
            "Unknown metric '#{namespace}.#{metric_name}'. " \
            'Please define it in your schema first.'
          )
        end
      end

      class InvalidTagError < SchemaError
        def initialize(metric_name, tag_name, allowed_tags)
          super(
            "Invalid tag '#{tag_name}' for metric '#{metric_name}'. " \
            "Allowed tags: #{allowed_tags.join(', ')}"
          )
        end
      end

      class MissingRequiredTagError < SchemaError
        def initialize(metric_name, required_tag, required_tags)
          super(
            "Missing required tag '#{required_tag}' for metric '#{metric_name}'. " \
            "Required tags: #{required_tags.join(', ')}"
          )
        end
      end

      class InvalidMetricTypeError < SchemaError
        def initialize(metric_name, expected_type, actual_type)
          super(
            "Invalid metric type for '#{metric_name}'. " \
            "Expected '#{expected_type}', got '#{actual_type}'"
          )
        end
      end

      class DuplicateMetricError < SchemaError
        def initialize(namespace, metric_name)
          super("Metric '#{namespace}.#{metric_name}' is already defined")
        end
      end

      class InvalidNamespaceError < SchemaError
        def initialize(namespace)
          super(
            "Unknown namespace '#{namespace}'. " \
            'Please define it in your schema first.'
          )
        end
      end
    end
  end
end
