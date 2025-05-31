# frozen_string_literal: true

require "colored2"
require "active_support/core_ext/string/inflections"

module Datadog
  class Statsd
    module Schema
      class SchemaError < StandardError
        attr_reader :namespace, :metric, :tag

        def initialize(message = nil, namespace: "<-no-namespace->", metric: "<-no-metric->", tag: "<-no-tag->")
          @namespace = namespace
          @metric = metric
          @tag = tag
          message ||= "#{self.class.name.underscore.gsub("_", " ").split(".").map(&:capitalize).join(" ")} Error " \
                      "{ namespace: #{namespace}, metric: #{metric}, tag: #{tag} }"
          super(message)
        end
      end

      class UnknownMetricError < SchemaError; end

      class InvalidTagError < SchemaError; end

      class MissingRequiredTagError < SchemaError; end

      class InvalidMetricTypeError < SchemaError; end

      class DuplicateMetricError < SchemaError; end

      class InvalidNamespaceError < SchemaError; end
    end
  end
end
