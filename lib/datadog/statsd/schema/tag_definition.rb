# frozen_string_literal: true

require "dry-struct"
require "dry-types"

# @author Datadog Team
# @since 0.1.0
module Datadog
  class Statsd
    # Schema definition and validation module for StatsD metrics
    module Schema
      # Represents a tag definition within a schema namespace
      # Defines validation rules, allowed values, transformations, and type constraints for tags
      # @example Basic tag definition
      #   tag_def = TagDefinition.new(
      #     name: :environment,
      #     values: [:production, :staging, :development],
      #     type: :symbol
      #   )
      # @example Tag with custom validation
      #   tag_def = TagDefinition.new(
      #     name: :user_id,
      #     type: :integer,
      #     validate: ->(value) { value > 0 }
      #   )
      # @author Datadog Team
      # @since 0.1.0
      class TagDefinition < Dry::Struct
        # Include the types module for easier access to Dry::Types
        module Types
          include Dry.Types()
        end

        # The tag name as a symbol
        # @return [Symbol] Tag name
        attribute :name, Types::Strict::Symbol

        # Allowed values for this tag (can be Array, Regexp, Proc, or single value)
        # @return [Array, Regexp, Proc, Object, nil] Allowed values constraint
        attribute :values, Types::Any.optional.default(nil)

        # The expected data type for tag values
        # @return [Symbol] Type constraint (:string, :integer, :symbol)
        attribute :type, Types::Strict::Symbol.default(:string)

        # Array of transformation functions to apply to values
        # @return [Array<Symbol>] Transformation function names
        attribute :transform, Types::Array.of(Types::Symbol).default([].freeze)

        # Custom validation procedure for tag values
        # @return [Proc, nil] Custom validation function
        attribute :validate, Types::Any.optional.default(nil)

        # The namespace this tag belongs to
        # @return [Symbol, nil] Namespace name
        attribute :namespace, Types::Strict::Symbol.optional.default(nil)

        # Check if a value is allowed for this tag according to the values constraint
        # @param value [Object] The value to check
        # @return [Boolean] true if the value is allowed
        # @example
        #   tag_def = TagDefinition.new(name: :env, values: [:prod, :dev])
        #   tag_def.allows_value?(:prod)  # => true
        #   tag_def.allows_value?(:test)  # => false
        def allows_value?(value)
          return true if values.nil? # No restrictions

          case values
          when Array
            values.include?(value) || values.include?(value.to_s) || values.include?(value.to_sym)
          when Regexp
            values.match?(value.to_s)
          when Proc
            values.call(value)
          else
            values == value
          end
        end

        # Apply transformations to a value using the provided transformer functions
        # @param value [Object] The value to transform
        # @param transformers [Hash<Symbol, Proc>] Hash of transformer name to proc mappings
        # @return [Object] The transformed value
        # @example
        #   tag_def = TagDefinition.new(name: :service, transform: [:downcase])
        #   transformers = { downcase: ->(val) { val.to_s.downcase } }
        #   tag_def.transform_value("WEB-SERVICE", transformers)  # => "web-service"
        def transform_value(value, transformers = {})
          return value if transform.empty?

          transform.reduce(value) do |val, transformer_name|
            transformer = transformers[transformer_name]
            transformer ? transformer.call(val) : val
          end
        end

        # Validate a value using type checking, transformations, and custom validation
        # @param value [Object] The value to validate
        # @param transformers [Hash<Symbol, Proc>] Hash of transformer name to proc mappings
        # @return [Boolean] true if the value is valid
        # @example
        #   tag_def = TagDefinition.new(
        #     name: :port,
        #     type: :integer,
        #     validate: ->(val) { val > 0 && val < 65536 }
        #   )
        #   tag_def.valid_value?(8080)   # => true
        #   tag_def.valid_value?(-1)     # => false
        def valid_value?(value, transformers = {})
          transformed_value = transform_value(value, transformers)

          # Apply type validation
          case type
          when :integer
            return false unless transformed_value.is_a?(Integer) || transformed_value.to_s.match?(/^\d+$/)
          when :string
            # strings are generally permissive
          when :symbol
            # symbols are generally permissive, will be converted
          end

          # Apply custom validation if present
          return validate.call(transformed_value) if validate.is_a?(Proc)

          # Apply value restrictions
          allows_value?(transformed_value)
        end
      end
    end
  end
end
