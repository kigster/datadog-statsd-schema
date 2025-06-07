# frozen_string_literal: true

require "datadog/statsd"
require "active_support/core_ext/module/delegation"

require_relative "schema/version"
require_relative "schema/errors"
require_relative "schema/tag_definition"
require_relative "schema/metric_definition"
require_relative "schema/namespace"
require_relative "schema/schema_builder"
require_relative "schema/analyzer"
require_relative "schema/cli"
require_relative "emitter"

# @author Konstantin Gredeskoul @ https://github.com/kigster
# @since 0.1.0
# @see https://github.com/DataDog/dogstatsd-ruby
module Datadog
  # Main StatsD client class that provides factory methods for creating emitters and schemas
  # @see Datadog::Statsd::Emitter
  # @see Datadog::Statsd::Schema
  class Statsd
    class << self
      # Factory method to create a new Emitter instance
      # @param args [Array] Arguments passed to Emitter.new
      # @return [Datadog::Statsd::Emitter] A new emitter instance
      # @see Datadog::Statsd::Emitter#initialize
      def emitter(...)
        ::Datadog::Statsd::Emitter.new(...)
      end

      # Factory method to create a new Schema instance
      # @param block [Proc] Block to define the schema structure
      # @return [Datadog::Statsd::Schema::Namespace] A new schema namespace
      # @see Datadog::Statsd::Schema.new
      def schema(...)
        ::Datadog::Statsd::Schema.new(...)
      end
    end

    # Schema definition and validation module for StatsD metrics
    # Provides a DSL for defining metric schemas with type safety and validation
    # @example Basic schema definition
    #   schema = Datadog::Statsd::Schema.new do
    #     namespace :web do
    #       tags do
    #         tag :environment, values: [:production, :staging, :development]
    #         tag :service, type: :string
    #       end
    #
    #       metrics do
    #         counter :requests_total, tags: { required: [:environment, :service] }
    #         gauge :memory_usage, tags: { allowed: [:environment] }
    #       end
    #     end
    #   end
    # @author Datadog Team
    # @since 0.1.0
    module Schema
      # Base error class for all schema-related errors
      # @see Datadog::Statsd::Schema::SchemaError
      class Error < StandardError
      end

      class << self
        # Controls whether the schema is in test mode
        # When true, colored output is disabled for test environments
        # @return [Boolean] Test mode flag
        attr_accessor :in_test
      end

      self.in_test = false

      # Create a new schema definition using the provided block
      # @param block [Proc] Block containing schema definition DSL
      # @return [Datadog::Statsd::Schema::Namespace] Root namespace of the schema
      # @example
      #   schema = Datadog::Statsd::Schema.new do
      #     namespace :app do
      #       tags do
      #         tag :env, values: [:prod, :dev]
      #       end
      #       metrics do
      #         counter :requests
      #       end
      #     end
      #   end
      def self.new(&)
        builder = SchemaBuilder.new
        builder.instance_eval(&) if block_given?
        builder.build
      end

      # Load schema definition from a file
      # @param path [String] Path to the schema definition file
      # @return [Datadog::Statsd::Schema::Namespace] Root namespace of the loaded schema
      # @raise [Errno::ENOENT] If the file doesn't exist
      # @example
      #   schema = Datadog::Statsd::Schema.load_file("config/metrics_schema.rb")
      def self.load_file(path)
        builder = SchemaBuilder.new
        builder.instance_eval(File.read(path), path)
        builder.build
      end

      # Configure global schema settings
      # @param block [Proc] Configuration block
      # @yield [Configuration] Configuration object for setting global options
      # @example
      #   Datadog::Statsd::Schema.configure do |config|
      #     config.statsd = Datadog::Statsd.new('localhost', 8125)
      #     config.tags = { environment: 'production' }
      #   end
      def self.configure
        yield configuration
      end

      # Get the global configuration object
      # @return [Datadog::Statsd::Schema::Configuration] Global configuration instance
      def self.configuration
        @configuration ||= Configuration.new
      end

      # Global configuration class for schema settings
      # Manages global StatsD client instance, schema, and tags
      class Configuration
        # Global StatsD client instance
        # @return [Datadog::Statsd, nil] StatsD client or nil if not configured
        attr_accessor :statsd

        # Global schema instance
        # @return [Datadog::Statsd::Schema::Namespace, nil] Schema or nil if not configured
        attr_accessor :schema

        # Global tags to be applied to all metrics
        # @return [Hash] Hash of global tags
        attr_accessor :tags

        # Initialize a new configuration with default values
        def initialize
          @statsd = nil
          @schema = nil
          @tags = {}
        end
      end
    end
  end
end
