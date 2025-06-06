# frozen_string_literal: true

require_relative "namespace"
require_relative "tag_definition"
require_relative "metric_definition"

# @author Datadog Team
# @since 0.1.0
module Datadog
  class Statsd
    # Schema definition and validation module for StatsD metrics
    module Schema
      # Builder class for constructing metric schemas using a DSL
      # Provides a fluent interface for defining namespaces, tags, and metrics
      # @example Basic schema building
      #   builder = SchemaBuilder.new
      #   builder.namespace :web do
      #     tags do
      #       tag :controller, values: %w[users posts]
      #     end
      #     metrics do
      #       counter :page_views, tags: { required: [:controller] }
      #     end
      #   end
      #   schema = builder.build
      # @author Datadog Team
      # @since 0.1.0
      class SchemaBuilder
        # Hash of transformer functions available for tag transformations
        # @return [Hash<Symbol, Proc>] Transformer name to proc mapping
        attr_reader :transformers

        # The root namespace of the schema being built
        # @return [Namespace] Root namespace instance
        attr_reader :root_namespace

        # Initialize a new schema builder
        def initialize
          @transformers = {}
          @root_namespace = Namespace.new(name: :root)
        end

        # Define transformers that can be used by tag definitions
        # @yield [TransformerBuilder] Block for defining transformers
        # @return [Hash<Symbol, Proc>] Hash of defined transformers
        # @example
        #   builder.transformers do
        #     underscore { |value| value.to_s.underscore }
        #     downcase { |value| value.to_s.downcase }
        #   end
        def transformers(&)
          return @transformers unless block_given?

          TransformerBuilder.new(@transformers).instance_eval(&)
        end

        # Define a namespace
        # @param name [Symbol] Name of the namespace
        # @yield [NamespaceBuilder] Block for defining namespace contents
        # @return [void]
        # @example
        #   builder.namespace :web do
        #     description "Web application metrics"
        #     # ... tags and metrics definitions
        #   end
        def namespace(name, &)
          builder = NamespaceBuilder.new(name, @transformers)
          builder.instance_eval(&) if block_given?
          namespace_def = builder.build

          @root_namespace = @root_namespace.add_namespace(namespace_def)
        end

        # Build the final schema (returns the root namespace)
        # @return [Namespace] The root namespace containing the entire schema
        def build
          @root_namespace
        end

        # Validate the schema for consistency
        # @raise [SchemaError] If schema validation fails
        # @return [void]
        def validate!
          errors = @root_namespace.validate_tag_references
          raise SchemaError, "Schema validation failed: #{errors.join(", ")}" unless errors.empty?
        end

        # Helper class for building transformers within the DSL
        # @api private
        class TransformerBuilder
          # Initialize with the transformers hash
          # @param transformers [Hash] Hash to store transformer definitions
          def initialize(transformers)
            @transformers = transformers
          end

          # Dynamic method to define transformers
          # @param name [Symbol] Name of the transformer
          # @param proc [Proc] Transformer procedure (alternative to block)
          # @yield [Object] Value to transform
          # @return [void]
          def method_missing(name, proc = nil, &block)
            @transformers[name.to_sym] = proc || block
          end

          # Always respond to any method for transformer definition
          # @param _name [Symbol] Method name
          # @param _include_private [Boolean] Whether to include private methods
          # @return [Boolean] Always true
          def respond_to_missing?(_name, _include_private = false)
            true
          end
        end

        # Helper class for building namespaces within the DSL
        # @api private
        class NamespaceBuilder
          # Name of the namespace being built
          # @return [Symbol] Namespace name
          attr_reader :name

          # Available transformers for tags
          # @return [Hash<Symbol, Proc>] Transformer definitions
          attr_reader :transformers

          # Tag definitions for this namespace
          # @return [Hash<Symbol, TagDefinition>] Tag definitions
          attr_reader :tags

          # Metric definitions for this namespace
          # @return [Hash<Symbol, MetricDefinition>] Metric definitions
          attr_reader :metrics

          # Nested namespaces
          # @return [Hash<Symbol, Namespace>] Nested namespace definitions
          attr_reader :namespaces

          # Description of this namespace
          # @return [String, nil] Description text
          attr_reader :description

          # Initialize a new namespace builder
          # @param name [Symbol] Name of the namespace
          # @param transformers [Hash] Available transformer functions
          def initialize(name, transformers = {})
            @name = name.to_sym
            @transformers = transformers
            @tags = {}
            @metrics = {}
            @namespaces = {}
            @description = nil
          end

          # Set description for this namespace
          # @param desc [String] Description text
          # @return [void]
          def description(desc)
            @description = desc
          end

          # Define tags for this namespace
          # @yield [TagsBuilder] Block for defining tags
          # @return [void]
          # @example
          #   tags do
          #     tag :controller, values: %w[users posts]
          #     tag :action, values: %w[index show create]
          #   end
          def tags(&)
            TagsBuilder.new(@tags, @transformers).instance_eval(&)
          end

          # Define metrics for this namespace
          # @yield [MetricsBuilder] Block for defining metrics
          # @return [void]
          # @example
          #   metrics do
          #     counter :page_views, tags: { required: [:controller] }
          #     gauge :memory_usage
          #   end
          def metrics(&)
            MetricsBuilder.new(@metrics, @transformers).instance_eval(&)
          end

          # Define nested namespace
          # @param name [Symbol] Name of the nested namespace
          # @yield [NamespaceBuilder] Block for defining nested namespace
          # @return [void]
          def namespace(name, &)
            builder = NamespaceBuilder.new(name, @transformers)
            builder.instance_eval(&) if block_given?
            @namespaces[name.to_sym] = builder.build
          end

          # Build the namespace instance
          # @return [Namespace] The constructed namespace
          def build
            Namespace.new(
              name: @name,
              description: @description,
              tags: @tags,
              metrics: @metrics,
              namespaces: @namespaces
            )
          end
        end

        # Helper class for building tags within a namespace
        # @api private
        class TagsBuilder
          # Initialize with tags hash and transformers
          # @param tags [Hash] Hash to store tag definitions
          # @param transformers [Hash] Available transformer functions
          def initialize(tags, transformers)
            @tags = tags
            @transformers = transformers
          end

          # Define a tag
          # @param name [Symbol] Name of the tag
          # @param options [Hash] Tag options
          # @option options [Array, Regexp, Proc] :values Allowed values
          # @option options [Symbol] :type Data type (:string, :integer, :symbol)
          # @option options [Array<Symbol>] :transform Transformation functions to apply
          # @option options [Proc] :validate Custom validation function
          # @return [void]
          # @example
          #   tag :controller, values: %w[users posts], type: :string
          #   tag :status_code, type: :integer, validate: ->(code) { (100..599).include?(code) }
          def tag(name, **options)
            tag_def = TagDefinition.new(
              name: name.to_sym,
              values: options[:values],
              type: options[:type] || :string,
              transform: Array(options[:transform] || []),
              validate: options[:validate],
              namespace: @current_namespace
            )
            @tags[name.to_sym] = tag_def
          end
        end

        # Helper class for building metrics within a namespace
        # @api private
        class MetricsBuilder
          # Initialize with metrics hash and transformers
          # @param metrics [Hash] Hash to store metric definitions
          # @param transformers [Hash] Available transformer functions
          def initialize(metrics, transformers)
            @metrics = metrics
            @transformers = transformers
            @current_namespace = nil
          end

          # Define a nested namespace for metrics
          # @param name [Symbol] Namespace name
          # @yield Block for defining metrics within the namespace
          # @return [void]
          def namespace(name, &)
            @current_namespace = name.to_sym
            instance_eval(&)
            @current_namespace = nil
          end

          # Define individual metric types
          %i[counter gauge histogram distribution timing set].each do |metric_type|
            # Define a metric of the specified type
            # @param name [Symbol] Metric name
            # @param options [Hash] Metric options
            # @option options [String] :description Human-readable description
            # @option options [Hash, Array] :tags Tag configuration
            # @option options [String] :inherit_tags Path to metric to inherit from
            # @option options [String] :units Unit of measurement
            # @yield [MetricBuilder] Block for additional metric configuration
            # @return [void]
            define_method(metric_type) do |name, **options, &block|
              metric_name = @current_namespace ? :"#{@current_namespace}_#{name}" : name.to_sym

              metric_def = MetricDefinition.new(
                name: metric_name,
                type: metric_type,
                description: options[:description],
                allowed_tags: extract_allowed_tags(options),
                required_tags: extract_required_tags(options),
                inherit_tags: options[:inherit_tags],
                units: options[:units],
                namespace: @current_namespace
              )

              unless block.nil?
                metric_builder = MetricBuilder.new(metric_def)
                metric_builder.instance_eval(&block)
                metric_def = metric_builder.build
              end

              @metrics[metric_name] = metric_def
            end
          end

          private

          # Extract allowed tags from options
          # @param options [Hash] Metric options
          # @return [Array<Symbol>] Allowed tag names
          def extract_allowed_tags(options)
            tags_option = options[:tags]
            return [] unless tags_option

            if tags_option.is_a?(Hash)
              Array(tags_option[:allowed] || []).map(&:to_sym)
            else
              Array(tags_option).map(&:to_sym)
            end
          end

          # Extract required tags from options
          # @param options [Hash] Metric options
          # @return [Array<Symbol>] Required tag names
          def extract_required_tags(options)
            tags_option = options[:tags]
            return [] unless tags_option

            if tags_option.is_a?(Hash)
              Array(tags_option[:required] || []).map(&:to_sym)
            else
              []
            end
          end
        end

        # Helper class for building individual metrics with block syntax
        # @api private
        class MetricBuilder
          # Initialize with a metric definition
          # @param metric_def [MetricDefinition] Initial metric definition
          def initialize(metric_def)
            @metric_def = metric_def
          end

          # Set metric description
          # @param desc [String] Description text
          # @return [void]
          def description(desc)
            @metric_def = @metric_def.new(description: desc)
          end

          # Configure metric tags
          # @param options [Hash] Tag configuration
          # @option options [Array] :allowed Allowed tag names
          # @option options [Array] :required Required tag names
          # @return [void]
          def tags(**options)
            allowed = Array(options[:allowed] || []).map(&:to_sym)
            required = Array(options[:required] || []).map(&:to_sym)

            @metric_def = @metric_def.new(
              allowed_tags: allowed,
              required_tags: required
            )
          end

          # Set metric units
          # @param unit_name [String] Unit description
          # @return [void]
          def units(unit_name)
            @metric_def = @metric_def.new(units: unit_name)
          end

          # Set metric inheritance
          # @param metric_path [String] Path to parent metric
          # @return [void]
          def inherit_tags(metric_path)
            @metric_def = @metric_def.new(inherit_tags: metric_path)
          end

          # Build the final metric definition
          # @return [MetricDefinition] The constructed metric definition
          def build
            @metric_def
          end
        end
      end
    end
  end
end
