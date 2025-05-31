# frozen_string_literal: true

require 'dry-struct'
require 'dry-types'

module Datadog
  class Statsd
    module Schema
      class TagDefinition < Dry::Struct
        # Include the types module for easier access
        module Types
          include Dry.Types()
        end

        attribute :name, Types::Strict::Symbol
        attribute :values, Types::Any.optional.default(nil) # Allow any type: Array, Regexp, Proc, or single value
        attribute :type, Types::Strict::Symbol.default(:string)
        attribute :transform, Types::Array.of(Types::Symbol).default([].freeze)
        attribute :validate, Types::Any.optional.default(nil) # Proc for custom validation

        # Check if a value is allowed for this tag
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

        # Apply transformations to a value
        def transform_value(value, transformers = {})
          return value if transform.empty?

          transform.reduce(value) do |val, transformer_name|
            transformer = transformers[transformer_name]
            transformer ? transformer.call(val) : val
          end
        end

        # Validate a value using custom validation if present
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
          if validate.is_a?(Proc)
            return validate.call(transformed_value)
          end

          # Apply value restrictions
          allows_value?(transformed_value)
        end
      end
    end
  end
end
