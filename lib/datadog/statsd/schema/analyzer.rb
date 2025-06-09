# frozen_string_literal: true

require "stringio"
require "colored2"
require "forwardable"
require "json"
require "yaml"

module Datadog
  class Statsd
    module Schema
      # Result structure for schema analysis
      # @!attribute [r] total_unique_metrics
      #   @return [Integer] Total number of unique metric names (including expansions)
      # @!attribute [r] metrics_analysis
      #   @return [Array<MetricAnalysis>] Analysis for each metric
      # @!attribute [r] total_possible_custom_metrics
      #   @return [Integer] Total number of possible custom metric combinations
      AnalysisResult = Data.define(
        :total_unique_metrics,
        :metrics_analysis,
        :total_possible_custom_metrics
      )

      # Analysis data for individual metrics
      # @!attribute [r] metric_name
      #   @return [String] Full metric name
      # @!attribute [r] metric_type
      #   @return [Symbol] Type of metric (:counter, :gauge, etc.)
      # @!attribute [r] expanded_names
      #   @return [Array<String>] All expanded metric names (for gauge/distribution/histogram)
      # @!attribute [r] unique_tags
      #   @return [Integer] Number of unique tags for this metric
      # @!attribute [r] unique_tag_values
      #   @return [Integer] Total number of unique tag values across all tags
      # @!attribute [r] total_combinations
      #   @return [Integer] Total possible tag value combinations for this metric
      MetricAnalysis = Data.define(
        :metric_name,
        :metric_type,
        :expanded_names,
        :unique_tags,
        :unique_tag_values,
        :total_combinations
      )

      # Analyzes schema instances to provide comprehensive metrics statistics
      class Analyzer
        # Metric suffixes for different metric types that create multiple metrics
        METRIC_EXPANSIONS = {
          gauge: %w[count min max sum avg],
          distribution: %w[count min max sum avg p50 p75 p90 p95 p99],
          histogram: %w[count min max sum avg]
        }.freeze

        attr_reader :schemas, :stdout, :stderr, :color, :format, :analysis_result

        SUPPORTED_FORMATS = %i[text json yaml].freeze

        # Initialize analyzer with schema(s)
        # @param schemas [Datadog::Statsd::Schema::Namespace, Array<Datadog::Statsd::Schema::Namespace>]
        #   Single schema or array of schemas to analyze
        def initialize(
          schemas,
          stdout: $stdout,
          stderr: $stderr,
          color: true,
          format: SUPPORTED_FORMATS.first
        )
          @schemas = Array(schemas)
          @stdout = stdout
          @stderr = stderr
          @color = color
          @format = format.to_sym

          raise ArgumentError, "Unsupported format: #{format}. Supported formats are: #{SUPPORTED_FORMATS.join(", ")}" unless SUPPORTED_FORMATS.include?(format)

          if color
            Colored2.enable!
          else
            Colored2.disable!
          end

          @analysis_result = analyze
        end

        # Perform comprehensive analysis of the schemas
        # @return [AnalysisResult] Complete analysis results
        def analyze
          all_metrics = collect_all_metrics
          metrics_analysis = analyze_metrics(all_metrics).map(&:to_h)

          total_unique_metrics = metrics_analysis.sum { |analysis| analysis[:expanded_names].size }
          total_possible_custom_metrics = metrics_analysis.sum { |e| e[:total_combinations] }

          AnalysisResult.new(
            total_unique_metrics:,
            metrics_analysis:,
            total_possible_custom_metrics:
          )
        end

        def render
          case format
          when :text
            TextFormatter.new(stdout:, stderr:, color:, analysis_result:).render
          when :json
            JSONFormatter.new(stdout:, stderr:, color:, analysis_result:).render
          when :yaml
            YAMLFormatter.new(stdout:, stderr:, color:, analysis_result:).render
          else
            raise ArgumentError, "Unsupported format: #{format}. Supported formats are: #{SUPPORTED_FORMATS.join(", ")}"
          end
        end

        private

        # Collect all metrics from all schemas with their context
        # @return [Array<Hash>] Array of metric info hashes
        def collect_all_metrics
          all_metrics = []

          @schemas.each do |schema|
            schema_metrics = schema.all_metrics
            schema_metrics.each do |metric_full_name, metric_info|
              all_metrics << {
                full_name: metric_full_name,
                definition: metric_info[:definition],
                namespace: metric_info[:namespace],
                namespace_path: metric_info[:namespace_path]
              }
            end
          end

          all_metrics
        end

        # Analyze each metric for tags and combinations
        # @param all_metrics [Array<Hash>] Collected metrics
        # @return [Array<MetricAnalysis>] Analysis for each metric
        def analyze_metrics(all_metrics)
          all_metrics.map do |metric_info|
            analyze_single_metric(metric_info)
          end
        end

        # Analyze a single metric
        # @param metric_info [Hash] Metric information
        # @return [MetricAnalysis] Analysis for this metric
        def analyze_single_metric(metric_info)
          definition = metric_info[:definition]
          namespace = metric_info[:namespace]
          namespace_path = metric_info[:namespace_path]
          full_name = metric_info[:full_name]

          # Get expanded metric names based on type
          expanded_names = get_expanded_metric_names(full_name, definition.type)

          # Build effective tags including parent namespace tags
          effective_tags = build_effective_tags_for_metric(namespace, namespace_path)
          available_tag_definitions = collect_available_tags(definition, effective_tags)

          # Calculate tag statistics
          unique_tags = available_tag_definitions.size
          unique_tag_values = available_tag_definitions.values.sum { |tag_def| count_tag_values(tag_def) }

          # Calculate total combinations (cartesian product of all tag values)
          total_combinations = calculate_tag_combinations(available_tag_definitions) * expanded_names.size

          MetricAnalysis.new(
            metric_name: full_name,
            metric_type: definition.type,
            expanded_names: expanded_names,
            unique_tags: unique_tags,
            unique_tag_values: unique_tag_values,
            total_combinations: total_combinations
          )
        end

        # Build effective tags for a metric including parent namespace tags
        # @param namespace [Namespace] The immediate namespace containing the metric
        # @param namespace_path [Array<Symbol>] Full path to the namespace
        # @return [Hash] Hash of effective tag definitions
        def build_effective_tags_for_metric(namespace, namespace_path)
          effective_tags = {}

          # Start from the root and build up tags through the hierarchy
          current_path = []

          # Find and traverse parent namespaces to collect their tags
          @schemas.each do |schema|
            # Traverse the namespace path to collect parent tags
            namespace_path.each do |path_segment|
              # Skip :root as it's just the schema root
              next if path_segment == :root

              current_path << path_segment

              # Find the namespace at this path
              path_str = current_path.join(".")
              found_namespace = schema.find_namespace_by_path(path_str)

              next unless found_namespace

              # Add tags from this namespace level
              found_namespace.tags.each do |tag_name, tag_def|
                effective_tags[tag_name] = tag_def
              end
            end

            break if effective_tags.any? # Found the schema with our namespaces
          end

          # Add the immediate namespace's tags (these take precedence)
          namespace.tags.each do |tag_name, tag_def|
            effective_tags[tag_name] = tag_def
          end

          effective_tags
        end

        # Get expanded metric names for types that create multiple metrics
        # @param base_name [String] Base metric name
        # @param metric_type [Symbol] Type of the metric
        # @return [Array<String>] All metric names this creates
        def get_expanded_metric_names(base_name, metric_type)
          expansions = METRIC_EXPANSIONS[metric_type]

          if expansions
            # For metrics that expand, create name.suffix for each expansion
            expansions.map { |suffix| "#{base_name}.#{suffix}" }
          else
            # For simple metrics, just return the base name
            [base_name]
          end
        end

        # Collect all tags available to a metric
        # @param definition [MetricDefinition] The metric definition
        # @param effective_tags [Hash] Tags available in the namespace
        # @return [Hash] Hash of tag name to tag definition
        def collect_available_tags(definition, effective_tags)
          available_tags = {}

          # Handle tag inheritance from other metrics first
          if definition.inherit_tags
            inherited_tags = resolve_inherited_tags(definition.inherit_tags)
            inherited_tags.keys
            inherited_tags.each do |tag_name, tag_def|
              available_tags[tag_name] = tag_def
            end
          end

          # Determine which additional tags to include based on metric's tag specification
          if definition.allowed_tags.any? || definition.required_tags.any?
            # If metric specifies allowed or required tags, only include those + inherited tags
            additional_tag_names = (definition.allowed_tags + definition.required_tags).map(&:to_sym).uniq

            additional_tag_names.each do |tag_name|
              available_tags[tag_name] = effective_tags[tag_name] if effective_tags[tag_name]
            end
          else
            # If no allowed or required tags specified, include all effective namespace tags
            # (This is the case when a metric doesn't restrict its tags)
            effective_tags.each do |tag_name, tag_def|
              available_tags[tag_name] = tag_def unless available_tags[tag_name]
            end
          end

          available_tags
        end

        # Resolve inherited tags from a parent metric path
        # @param inherit_path [String] Dot-separated path to parent metric
        # @return [Hash] Hash of inherited tag definitions
        def resolve_inherited_tags(inherit_path)
          inherited_tags = {}

          @schemas.each do |schema|
            # Find the parent metric in the schema
            all_metrics = schema.all_metrics
            parent_metric_info = all_metrics[inherit_path]

            next unless parent_metric_info

            parent_definition = parent_metric_info[:definition]
            parent_namespace = parent_metric_info[:namespace]
            parent_namespace_path = parent_metric_info[:namespace_path]

            # Build effective tags for the parent metric (including its own parent namespace tags)
            parent_effective_tags = build_effective_tags_for_metric(parent_namespace, parent_namespace_path)

            # Recursively resolve parent's inherited tags first
            if parent_definition.inherit_tags
              parent_inherited = resolve_inherited_tags(parent_definition.inherit_tags)
              inherited_tags.merge!(parent_inherited)
            end

            # Get the tags that are actually available to the parent metric
            parent_available_tags = collect_parent_available_tags(parent_definition, parent_effective_tags)
            inherited_tags.merge!(parent_available_tags)

            break # Found the parent metric, stop searching
          end

          inherited_tags
        end

        # Collect available tags for a parent metric (without recursion to avoid infinite loops)
        # @param definition [MetricDefinition] The parent metric definition
        # @param effective_tags [Hash] Tags available in the parent's namespace
        # @return [Hash] Hash of tag name to tag definition
        def collect_parent_available_tags(definition, effective_tags)
          available_tags = {}

          # Start with all effective tags from namespace
          effective_tags.each do |tag_name, tag_def|
            available_tags[tag_name] = tag_def
          end

          # Apply parent metric's tag restrictions
          if definition.allowed_tags.any?
            allowed_and_required_tags = (definition.allowed_tags + definition.required_tags).map(&:to_sym).uniq
            available_tags.select! { |tag_name, _| allowed_and_required_tags.include?(tag_name) }
          end

          available_tags
        end

        # Count the number of possible values for a tag
        # @param tag_definition [TagDefinition] The tag definition
        # @return [Integer] Number of possible values
        def count_tag_values(tag_definition)
          if tag_definition.values.nil?
            # If no values specified, assume it can have any value (estimate)
            100 # Conservative estimate for open-ended tags
          elsif tag_definition.values.is_a?(Array)
            tag_definition.values.size
          elsif tag_definition.values.is_a?(Regexp)
            # For regex, we can't know exact count, use estimate
            50 # Conservative estimate for regex patterns
          else
            1 # Single value
          end
        end

        # Calculate total possible combinations of tag values
        # @param tag_definitions [Hash] Hash of tag name to definition
        # @return [Integer] Total combinations possible
        def calculate_tag_combinations(tag_definitions)
          return 1 if tag_definitions.empty?

          # Multiply the number of possible values for each tag
          tag_definitions.values.reduce(1) do |total, tag_def|
            total * count_tag_values(tag_def)
          end
        end

        # ——————————————————————————————————————————————————————————————————————————————————————————————————————————————-
        # Formatter classes
        # ——————————————————————————————————————————————————————————————————————————————————————————————————————————————-
        class BaseFormatter
          attr_reader :stdout, :stderr, :color,
                      :analysis_result,
                      :total_unique_metrics,
                      :metrics_analysis,
                      :total_possible_custom_metrics

          def initialize(stdout:, stderr:, color:, analysis_result:)
            @stdout = stdout
            @stderr = stderr
            @color = color
            @analysis_result = analysis_result.to_h.transform_values { |v| v.is_a?(Data) ? v.to_h : v }
            @total_unique_metrics = @analysis_result[:total_unique_metrics]
            @metrics_analysis = @analysis_result[:metrics_analysis]
            @total_possible_custom_metrics = @analysis_result[:total_possible_custom_metrics]
          end

          def render
            raise NotImplementedError, "Subclasses must implement this method"
          end
        end

        class TextFormatter < BaseFormatter
          attr_reader :output

          def render
            @output = StringIO.new
            format_analysis_output
            @output.string
          end

          private

          # Format the analysis output for display
          def format_analysis_output
            format_metric_analysis_header(output)

            analysis_result[:metrics_analysis].each do |analysis|
              output.puts
              format_metric_analysis(output, analysis)
              line(output, placement: :flat)
            end

            summary(
              output,
              analysis_result[:total_unique_metrics],
              analysis_result[:total_possible_custom_metrics]
            )
            output.string
          end

          def line(output, placement: :top)
            if placement == :top
              output.puts "┌──────────────────────────────────────────────────────────────────────────────────────────────┐".white.on.blue
            elsif placement == :bottom
              output.puts "└──────────────────────────────────────────────────────────────────────────────────────────────┘".white.on.blue
            elsif placement == :middle
              output.puts "├──────────────────────────────────────────────────────────────────────────────────────────────┤".white.on.blue
            elsif placement == :flat
              output.puts " ──────────────────────────────────────────────────────────────────────────────────────────────".white.bold
            end
          end

          def summary(output, total_unique_metrics, total_possible_custom_metrics)
            line(output)
            output.puts "│ Schema Analysis Results:                                                                     │".yellow.bold.on.blue
            output.puts "│                                        SUMMARY                                               │".white.on.blue
            line(output, placement: :bottom)
            output.puts
            output.puts "                     Total unique metrics: #{("%3d" % total_unique_metrics).bold.green}"
            output.puts "Total possible custom metric combinations: #{("%3d" % total_possible_custom_metrics).bold.green}"
            output.puts
          end

          def format_metric_analysis_header(output)
            line(output)
            output.puts "│ Detailed Metric Analysis:                                                                    │".white.on.blue
            line(output, placement: :bottom)
          end

          def format_metric_analysis(output, analysis)
            output.puts "  • #{analysis[:metric_type].to_s.cyan}('#{analysis[:metric_name].yellow.bold}')"
            if analysis[:expanded_names].size > 1
              output.puts  "    Expanded names:"
              output.print "      • ".yellow
              output.puts analysis[:expanded_names].join("\n      • ").yellow
            end
            output.puts
            output.puts "                              Unique tags: #{("%3d" % analysis[:unique_tags]).bold.green}"
            output.puts "                         Total tag values: #{("%3d" % analysis[:unique_tag_values]).bold.green}"
            output.puts "                    Possible combinations: #{("%3d" % analysis[:total_combinations]).bold.green}"
            output.puts
          end
        end

        # ——————————————————————————————————————————————————————————————————————————————————————————————————————————————-
        # JSON Formatter classes
        # ——————————————————————————————————————————————————————————————————————————————————————————————————————————————-
        class JSONFormatter < BaseFormatter
          def render
            JSON.pretty_generate(analysis_result.to_h)
          end
        end

        # ——————————————————————————————————————————————————————————————————————————————————————————————————————————————-
        # YAML Formatter classes
        # ——————————————————————————————————————————————————————————————————————————————————————————————————————————————-
        class YAMLFormatter < BaseFormatter
          def render
            YAML.dump(analysis_result.to_h)
          end
        end
      end
    end
  end
end
