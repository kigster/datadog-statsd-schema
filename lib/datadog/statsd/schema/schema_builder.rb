# frozen_string_literal: true

require_relative "namespace"
require_relative "tag_definition"
require_relative "metric_definition"

module Datadog
  class Statsd
    module Schema
      class SchemaBuilder
        attr_reader :transformers, :root_namespace

        def initialize
          @transformers = {}
          @root_namespace = Namespace.new(name: :root)
        end

        # Define transformers that can be used by tag definitions
        def transformers(&)
          return @transformers unless block_given?

          TransformerBuilder.new(@transformers).instance_eval(&)
        end

        # Define a namespace
        def namespace(name, &)
          builder = NamespaceBuilder.new(name, @transformers)
          builder.instance_eval(&) if block_given?
          namespace_def = builder.build

          @root_namespace = @root_namespace.add_namespace(namespace_def)
        end

        # Build the final schema (returns the root namespace)
        def build
          @root_namespace
        end

        # Validate the schema for consistency
        def validate!
          errors = @root_namespace.validate_tag_references
          raise SchemaError, "Schema validation failed: #{errors.join(", ")}" unless errors.empty?
        end

        # Helper class for building transformers
        class TransformerBuilder
          def initialize(transformers)
            @transformers = transformers
          end

          def method_missing(name, proc = nil, &block)
            @transformers[name.to_sym] = proc || block
          end

          def respond_to_missing?(_name, _include_private = false)
            true
          end
        end

        # Helper class for building namespaces
        class NamespaceBuilder
          attr_reader :name, :transformers, :tags, :metrics, :namespaces, :description

          def initialize(name, transformers = {})
            @name = name.to_sym
            @transformers = transformers
            @tags = {}
            @metrics = {}
            @namespaces = {}
            @description = nil
          end

          # Set description for this namespace
          def description(desc)
            @description = desc
          end

          # Define tags for this namespace
          def tags(&)
            TagsBuilder.new(@tags, @transformers).instance_eval(&)
          end

          # Define metrics for this namespace
          def metrics(&)
            MetricsBuilder.new(@metrics, @transformers).instance_eval(&)
          end

          # Define nested namespace
          def namespace(name, &)
            builder = NamespaceBuilder.new(name, @transformers)
            builder.instance_eval(&) if block_given?
            @namespaces[name.to_sym] = builder.build
          end

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
        class TagsBuilder
          def initialize(tags, transformers)
            @tags = tags
            @transformers = transformers
          end

          def tag(name, **options)
            tag_def = TagDefinition.new(
              name: name.to_sym,
              values: options[:values],
              type: options[:type] || :string,
              transform: Array(options[:transform] || []),
              validate: options[:validate]
            )
            @tags[name.to_sym] = tag_def
          end
        end

        # Helper class for building metrics within a namespace
        class MetricsBuilder
          def initialize(metrics, transformers)
            @metrics = metrics
            @transformers = transformers
            @current_namespace = nil
          end

          # Define a nested namespace for metrics
          def namespace(name, &)
            @current_namespace = name.to_sym
            instance_eval(&)
            @current_namespace = nil
          end

          # Define individual metric types
          %i[counter gauge histogram distribution timing set].each do |metric_type|
            define_method(metric_type) do |name, **options, &block|
              metric_name = @current_namespace ? :"#{@current_namespace}_#{name}" : name.to_sym

              metric_def = MetricDefinition.new(
                name: metric_name,
                type: metric_type,
                description: options[:description],
                allowed_tags: extract_allowed_tags(options),
                required_tags: extract_required_tags(options),
                inherit_tags: options[:inherit_tags],
                units: options[:units]
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

          def extract_allowed_tags(options)
            tags_option = options[:tags]
            return [] unless tags_option

            if tags_option.is_a?(Hash)
              Array(tags_option[:allowed] || []).map(&:to_sym)
            else
              Array(tags_option).map(&:to_sym)
            end
          end

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
        class MetricBuilder
          def initialize(metric_def)
            @metric_def = metric_def
          end

          def description(desc)
            @metric_def = @metric_def.new(description: desc)
          end

          def tags(**options)
            allowed = Array(options[:allowed] || []).map(&:to_sym)
            required = Array(options[:required] || []).map(&:to_sym)

            @metric_def = @metric_def.new(
              allowed_tags: allowed,
              required_tags: required
            )
          end

          def units(unit_name)
            @metric_def = @metric_def.new(units: unit_name)
          end

          def inherit_tags(metric_path)
            @metric_def = @metric_def.new(inherit_tags: metric_path)
          end

          def build
            @metric_def
          end
        end
      end
    end
  end
end
