# frozen_string_literal: true

require 'datadog/statsd'
require 'active_support/core_ext/module/delegation'

require_relative 'schema/version'
require_relative 'schema/errors'
require_relative 'schema/tag_definition'
require_relative 'schema/metric_definition'
require_relative 'schema/namespace'
require_relative 'schema/schema_builder'
require_relative 'schema/emitter'

module Datadog
  class Statsd
    module Schema
      class Error < StandardError
      end

      # Create a new schema definition
      def self.new(&)
        builder = SchemaBuilder.new
        builder.instance_eval(&) if block_given?
        builder.build
      end

      # Load schema from a file
      def self.load_file(path)
        builder = SchemaBuilder.new
        builder.instance_eval(File.read(path), path)
        builder.build
      end

      # Configure the global schema
      def self.configure
        yield configuration
      end

      def self.configuration
        @configuration ||= Configuration.new
      end

      # Configuration class for global settings
      class Configuration
        attr_accessor :statsd, :schema, :tags

        def initialize
          @statsd = nil
          @schema = nil
          @tags = {}
        end
      end
    end
  end
end
