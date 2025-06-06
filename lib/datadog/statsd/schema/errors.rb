# frozen_string_literal: true

require "colored2"
require "active_support/core_ext/string/inflections"

# @author Datadog Team
# @since 0.1.0
module Datadog
  class Statsd
    # Schema definition and validation module for StatsD metrics
    module Schema
      # Base error class for all schema validation errors
      # Provides context about where the error occurred including namespace, metric, and tag information
      # @abstract Base class for schema validation errors
      # @author Datadog Team
      # @since 0.1.0
      class SchemaError < StandardError
        # The namespace where the error occurred
        # @return [String] Namespace path or placeholder if not available
        attr_reader :namespace

        # The metric name where the error occurred
        # @return [String] Metric name or placeholder if not available
        attr_reader :metric

        # The tag name where the error occurred
        # @return [String] Tag name or placeholder if not available
        attr_reader :tag

        # Initialize a new schema error with context information
        # @param message [String, nil] Custom error message, will be auto-generated if nil
        # @param namespace [String] Namespace context for the error
        # @param metric [String] Metric context for the error
        # @param tag [String] Tag context for the error
        def initialize(message = nil, namespace: "<-no-namespace->", metric: "<-no-metric->", tag: "<-no-tag->")
          @namespace = namespace
          @metric = metric
          @tag = tag
          message ||= "#{self.class.name.underscore.gsub("_", " ").split(".").map(&:capitalize).join(" ")} Error " \
                      "{ namespace: #{namespace}, metric: #{metric}, tag: #{tag} }"
          super(message)
        end
      end

      # Raised when a metric is used that doesn't exist in the schema
      # @example
      #   # This would raise UnknownMetricError if 'unknown_metric' is not defined in the schema
      #   emitter.increment('unknown_metric')
      class UnknownMetricError < SchemaError; end

      # Raised when a tag is used that doesn't exist in the schema or is not allowed for the metric
      # @example
      #   # This would raise InvalidTagError if 'invalid_tag' is not allowed for the metric
      #   emitter.increment('valid_metric', tags: { invalid_tag: 'value' })
      class InvalidTagError < SchemaError; end

      # Raised when a required tag is missing from a metric call
      # @example
      #   # This would raise MissingRequiredTagError if 'environment' tag is required
      #   emitter.increment('metric_requiring_env_tag', tags: { service: 'web' })
      class MissingRequiredTagError < SchemaError; end

      # Raised when a metric is called with the wrong type
      # @example
      #   # This would raise InvalidMetricTypeError if 'response_time' is defined as a histogram
      #   emitter.increment('response_time')  # Should be emitter.histogram('response_time')
      class InvalidMetricTypeError < SchemaError; end

      # Raised when attempting to define a metric that already exists in the schema
      # @example Schema definition error
      #   namespace :web do
      #     metrics do
      #       counter :requests
      #       counter :requests  # This would raise DuplicateMetricError
      #     end
      #   end
      class DuplicateMetricError < SchemaError; end

      # Raised when a namespace definition is invalid
      # @example
      #   # This might be raised for namespace naming conflicts or invalid structure
      #   namespace :invalid_namespace do
      #     # ... invalid configuration
      #   end
      class InvalidNamespaceError < SchemaError; end
    end
  end
end
