# frozen_string_literal: true

require_relative 'schema/version'
require_relative 'schema/definition'
require_relative 'schema/metric_definition'
require_relative 'schema/namespace'
require_relative 'schema/schema_statsd'
require_relative 'schema/errors'

module Datadog
  module Statsd
    module Schema
      class Error < StandardError; end

      # Create a new schema definition
      def self.new(&)
        definition = Definition.new
        definition.instance_eval(&) if block_given?
        definition
      end

      # Load schema from a file
      def self.load_file(path)
        definition = Definition.new
        definition.instance_eval(File.read(path), path)
        definition
      end
    end
  end
end
