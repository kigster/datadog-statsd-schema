# frozen_string_literal: true

require "forwardable"
require "datadog/statsd"
require "ostruct"
require "active_support/core_ext/string/inflections"

# Load colored2 for error formatting if available
begin
  require "colored2"
rescue LoadError
  # colored2 not available, use plain text
end

# Load schema classes if available
begin
  require_relative "schema"
  require_relative "schema/namespace"
  require_relative "schema/errors"
rescue LoadError
  # Schema classes not available, validation will be skipped
end

module Datadog
  class Statsd
    class Emitter
      MUTEX = Mutex.new

      DEFAULT_HOST = "127.0.0.1"
      DEFAULT_PORT = 8125
      DEFAULT_NAMESPACE = nil
      DEFAULT_ARGUMENTS = { delay_serialization: true }
      DEFAULT_SAMPLE_RATE = 1.0
      DEFAULT_VALIDATION_MODE = :strict

      # @description This class is a wrapper around the Datadog::Statsd class. It provides a
      #     simple interface for sending metrics to Datadog. It also supports AB testing.
      #     When initialized with a schema, it validates metrics and tags against the schema.
      #
      #     @see Datadog::Statsd::Emitter.new for more details.
      #
      class << self
        attr_accessor :datadog_statsd

        # @return [Datadog::Statsd, NilClass] The Datadog Statsd client instance or nil if not
        #     currently connected.
        def statsd
          return @datadog_statsd if defined?(@datadog_statsd)

          @datadog_statsd = ::Datadog::Statsd::Schema.configuration.statsd
        end

        extend Forwardable
        def_delegators :datadog_statsd,
                       :increment,
                       :decrement,
                       :gauge,
                       :histogram,
                       :distribution,
                       :set,
                       :flush

        def global_tags
          @global_tags ||= OpenStruct.new
        end

        def configure
          yield(global_tags)
        end

        def connect(
          host: DEFAULT_HOST,
          port: DEFAULT_PORT,
          tags: {},
          sample_rate: DEFAULT_SAMPLE_RATE,
          namespace: DEFAULT_NAMESPACE,
          **opts
        )
          return @datadog_statsd if defined?(@datadog_statsd) && @datadog_statsd

          tags ||= {}
          tags = tags.merge(global_tags.to_h)
          tags = tags.map { |k, v| "#{k}:#{v}" }

          opts ||= {}
          # Remove any unknown parameters that Datadog::Statsd doesn't support
          opts = opts.except(:emitter) if opts.key?(:emitter)
          opts = DEFAULT_ARGUMENTS.merge(opts)

          MUTEX.synchronize do
            unless defined?(@datadog_statsd)
              @datadog_statsd =
                ::Datadog::Statsd.new(host, port, namespace:, tags:, sample_rate:, **opts)
            end
          end

          yield(datadog_statsd) if block_given?
        end

        def close
          begin
            @datadog_statsd&.close
          rescue StandardError
            nil
          end
          @datadog_statsd = nil
        end
      end

      attr_reader :tags, :ab_test, :sample_rate, :metric, :schema, :validation_mode

      def initialize(
        emitter = nil,
        metric: nil,
        tags: nil,
        ab_test: nil,
        sample_rate: nil,
        schema: nil,
        validation_mode: DEFAULT_VALIDATION_MODE
      )
        if emitter.nil? && metric.nil? && tags.nil? && ab_test.nil? && sample_rate.nil? && schema.nil?
          raise ArgumentError,
                "Datadog::Statsd::Emitter: use class methods if you are passing nothing to the constructor."
        end
        @sample_rate = sample_rate || 1.0
        @tags = tags || nil
        @tags.merge!(self.class.global_tags.to_h) if self.class.global_tags.present?

        @ab_test = ab_test || {}
        @metric = metric
        @schema = schema
        @validation_mode = validation_mode

        emitter =
          case emitter
          when String, Symbol
            emitter.to_s
          when Module, Class
            emitter.name
          else
            emitter&.class&.name
          end

        emitter = nil if emitter == "Object"
        emitter = emitter&.gsub("::", ".")&.underscore&.downcase

        return unless emitter

        @tags ||= {}
        @tags[:emitter] = emitter
      end

      def method_missing(m, *args, **opts, &)
        args, opts = normalize_arguments(*args, **opts)

        # If schema validation fails, handle based on validation mode
        if @schema && should_validate?(args)
          validation_result = validate_metric_call(m, *args, **opts)
          return if validation_result == :drop
        end

        if ENV.fetch("DATADOG_DEBUG", false)
          warn "<CUSTOM METRIC to STATSD>: #{self}->#{m}(#{args.join(", ")}, #{opts.inspect})"
        end
        statsd&.send(m, *args, **opts, &)
      end

      def respond_to_missing?(method, *)
        statsd&.respond_to? method
      end

      def normalize_arguments(*args, **opts)
        # Handle metric name - use constructor metric if none provided in method call
        normalized_args = args.dup

        if @metric
          if normalized_args.empty?
            normalized_args = [@metric]
          elsif normalized_args.first.nil?
            normalized_args[0] = @metric
          end
        end

        # Start with instance tags
        merged_tags = (@tags || {}).dup

        # Convert instance ab_test to tags
        (@ab_test || {}).each do |test_name, group|
          merged_tags[:ab_test_name] = test_name
          merged_tags[:ab_test_group] = group
        end

        # Handle ab_test from method call opts and remove it from opts
        normalized_opts = opts.dup
        if normalized_opts[:ab_test]
          normalized_opts[:ab_test].each do |test_name, group|
            merged_tags[:ab_test_name] = test_name
            merged_tags[:ab_test_group] = group
          end
          normalized_opts.delete(:ab_test)
        end

        # Merge with method call tags (method call tags take precedence)
        merged_tags = merged_tags.merge(normalized_opts[:tags]) if normalized_opts[:tags]

        # Set merged tags in opts if there are any
        normalized_opts[:tags] = merged_tags unless merged_tags.empty?

        # Handle sample_rate - use instance sample_rate if not provided in method call
        if @sample_rate && @sample_rate != 1.0 && !normalized_opts.key?(:sample_rate)
          normalized_opts[:sample_rate] = @sample_rate
        end

        [normalized_args, normalized_opts]
      end

      private

      def should_validate?(args)
        !args.empty? && args.first && @validation_mode != :off
      end

      def validate_metric_call(metric_method, *args, **opts)
        return unless @schema && !args.empty?

        metric_name = args.first
        return unless metric_name

        metric_type = normalize_metric_type(metric_method)
        provided_tags = opts[:tags] || {}

        begin
          validate_metric_exists(metric_name, metric_type)
          validate_metric_tags(metric_name, provided_tags)
        rescue Datadog::Statsd::Schema::SchemaError => e
          handle_validation_error(e)
        end
      end

      def validate_metric_exists(metric_name, metric_type)
        # Try to find the metric in the schema
        all_metrics = @schema.all_metrics

        # Look for exact match first
        metric_info = all_metrics[metric_name.to_s]

        unless metric_info
          # Look for partial matches to provide better error messages
          suggestions = find_metric_suggestions(metric_name, all_metrics.keys)
          error_message = "Unknown metric '#{metric_name}'"
          error_message += ". Did you mean: #{suggestions.join(", ")}?" if suggestions.any?
          error_message += ". Available metrics: #{all_metrics.keys.first(5).join(", ")}"
          error_message += ", ..." if all_metrics.size > 5

          raise Datadog::Statsd::Schema::UnknownMetricError.new(error_message, metric: metric_name)
        end

        # Validate metric type matches
        expected_type = metric_info[:definition].type
        return unless expected_type != metric_type

        error_message = "Invalid metric type for '#{metric_name}'. Expected '#{expected_type}', got '#{metric_type}'"
        raise Datadog::Statsd::Schema::InvalidMetricTypeError.new(
          error_message,
          namespace: metric_info[:namespace_path].join("."),
          metric: metric_name
        )
      end

      def validate_metric_tags(metric_name, provided_tags)
        all_metrics = @schema.all_metrics
        metric_info = all_metrics[metric_name.to_s]
        return unless metric_info

        metric_definition = metric_info[:definition]
        namespace = metric_info[:namespace]

        # Get effective tags including inherited ones from namespace
        effective_tags = namespace.effective_tags

        # Check for missing required tags
        missing_required = metric_definition.missing_required_tags(provided_tags)
        if missing_required.any?
          error_message = "Missing required tags for metric '#{metric_name}': #{missing_required.join(", ")}"
          error_message += ". Required tags: #{metric_definition.required_tags.join(", ")}"

          raise Datadog::Statsd::Schema::MissingRequiredTagError.new(
            error_message,
            namespace: metric_info[:namespace_path].join("."),
            metric: metric_name
          )
        end

        # Check for invalid tags (if metric has allowed_tags restrictions)
        # Exclude framework tags like 'emitter' from validation
        framework_tags = %i[emitter ab_test_name ab_test_group]
        user_provided_tags = provided_tags.reject { |key, _| framework_tags.include?(key.to_sym) }

        invalid_tags = metric_definition.invalid_tags(user_provided_tags)
        if invalid_tags.any?
          error_message = "Invalid tags for metric '#{metric_name}': #{invalid_tags.join(", ")}"
          if metric_definition.allowed_tags.any?
            error_message += ". Allowed tags: #{metric_definition.allowed_tags.join(", ")}"
          end

          raise Datadog::Statsd::Schema::InvalidTagError.new(
            error_message,
            namespace: metric_info[:namespace_path].join("."),
            metric: metric_name
          )
        end

        # Validate tag values against schema definitions (including framework tags)
        provided_tags.each do |tag_name, tag_value|
          # Skip validation for framework tags that don't have schema definitions
          next if framework_tags.include?(tag_name.to_sym) && !effective_tags[tag_name.to_sym]

          tag_definition = effective_tags[tag_name.to_sym]
          next unless tag_definition

          validate_tag_value(metric_name, tag_name, tag_value, tag_definition, metric_info)
        end
      end

      def validate_tag_value(metric_name, tag_name, tag_value, tag_definition, metric_info)
        # Type validation
        case tag_definition.type
        when :integer
          unless tag_value.is_a?(Integer) || (tag_value.is_a?(String) && tag_value.match?(/^\d+$/))
            raise Datadog::Statsd::Schema::InvalidTagError.new(
              "Tag '#{tag_name}' for metric '#{metric_name}' must be an integer, got #{tag_value.class}",
              namespace: metric_info[:namespace_path].join("."),
              metric: metric_name,
              tag: tag_name
            )
          end
        when :symbol
          unless tag_value.is_a?(Symbol) || tag_value.is_a?(String)
            raise Datadog::Statsd::Schema::InvalidTagError.new(
              "Tag '#{tag_name}' for metric '#{metric_name}' must be a symbol or string, got #{tag_value.class}",
              namespace: metric_info[:namespace_path].join("."),
              metric: metric_name,
              tag: tag_name
            )
          end
        end

        # Value validation
        if tag_definition.values
          normalized_value = tag_value.to_s
          allowed_values = Array(tag_definition.values).map(&:to_s)

          unless allowed_values.include?(normalized_value) ||
                 value_matches_pattern?(normalized_value, tag_definition.values)
            raise Datadog::Statsd::Schema::InvalidTagError.new(
              "Invalid value '#{tag_value}' for tag '#{tag_name}' in metric '#{metric_name}'. Allowed values: #{allowed_values.join(", ")}",
              namespace: metric_info[:namespace_path].join("."),
              metric: metric_name,
              tag: tag_name
            )
          end
        end

        # Custom validation
        return unless tag_definition.validate && tag_definition.validate.respond_to?(:call)
        return if tag_definition.validate.call(tag_value)

        raise Datadog::Statsd::Schema::InvalidTagError.new(
          "Custom validation failed for tag '#{tag_name}' with value '#{tag_value}' in metric '#{metric_name}'",
          namespace: metric_info[:namespace_path].join("."),
          metric: metric_name,
          tag: tag_name
        )
      end

      def value_matches_pattern?(value, patterns)
        Array(patterns).any? do |pattern|
          case pattern
          when Regexp
            value.match?(pattern)
          else
            false
          end
        end
      end

      def find_metric_suggestions(metric_name, available_metrics)
        # Simple fuzzy matching - find metrics that contain the metric name or vice versa
        suggestions = available_metrics.select do |available|
          available.include?(metric_name) || metric_name.include?(available) ||
            levenshtein_distance(metric_name, available) <= 2
        end
        suggestions.first(3) # Limit to 3 suggestions
      end

      def levenshtein_distance(str1, str2)
        # Simple Levenshtein distance implementation
        return str2.length if str1.empty?
        return str1.length if str2.empty?

        matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }

        (0..str1.length).each { |i| matrix[i][0] = i }
        (0..str2.length).each { |j| matrix[0][j] = j }

        (1..str1.length).each do |i|
          (1..str2.length).each do |j|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,     # deletion
              matrix[i][j - 1] + 1,     # insertion
              matrix[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        matrix[str1.length][str2.length]
      end

      def normalize_metric_type(method_name)
        case method_name.to_sym
        when :increment, :decrement, :count
          :counter
        when :gauge
          :gauge
        when :histogram
          :histogram
        when :distribution
          :distribution
        when :set
          :set
        when :timing
          :timing
        else
          method_name.to_sym
        end
      end

      def handle_validation_error(error)
        case @validation_mode
        when :strict
          # Only show colored output if not in test and colored2 is available
          if Datadog::Statsd::Schema.in_test
            warn "Schema Validation Error: #{error.message}"
          else
            warn "Schema Validation Error:\n • ".yellow + error.message.to_s.red
          end
          raise error
        when :warn
          # Only show colored output if not in test and colored2 is available
          if Datadog::Statsd::Schema.in_test
            warn "Schema Validation Warning: #{error.message}"
          else
            warn "Schema Validation Warning:\n • ".yellow + error.message.to_s.bold.yellow
          end
          nil # Continue execution
        when :drop
          :drop # Signal to drop the metric
        when :off
          nil # No validation - continue execution
        else
          raise error
        end
      end

      delegate :flush, to: :class

      delegate :statsd, to: :class
    end
  end
end
