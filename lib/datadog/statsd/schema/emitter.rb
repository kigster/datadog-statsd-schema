# frozen_string_literal: true

require 'forwardable'
require 'datadog/statsd'
require 'ostruct'

module Datadog
  class Statsd
    module Schema
      # ## Metric Types
      # @see https://docs.datadoghq.com/metrics/custom_metrics/dogstatsd_metrics_submission/?tab=ruby
      #
      # There are 5 total metric types you can send with Statsd, and it's important to understand the
      # differences:
      #
      # * COUNT             (eg, Datadog::Statsd::Schema::Emitter.increment('emails.sent', by: 2))
      # * GAUGE             (eg, Datadog::Statsd::Schema::Emitter.gauge('users.on.site', 100))
      # * HISTOGRAM         (eg, Datadog::Statsd::Schema::Emitter.histogram('page.load.time', 100))
      # * DISTRIBUTION      (eg, Datadog::Statsd::Schema::Emitter.distribution('page.load.time', 100))
      # * SET               (eg, Datadog::Statsd::Schema::Emitter.set('users.unique', '12345'))
      #
      # NOTE: that HISTOGRAM converts your metric into FIVE separate metrics (with suffixes .max, .median,
      # .avg, .count, p95), while DISTRIBUTION explodes into TEN separate metrics (see the documentation).
      # Do NOT use SET unless you know what you are doing.
      #
      # You can send metrics via class methods of Datadog::Statsd::Schema::Emitter, or by instantiating the class with
      # an emitterect or a string, which becomes the "emitter" tag value for the metric. For example:
      # @description This class is a wrapper around Datadog::Statsd class. It provides a simple
      #     interface for sending metrics to Datadog via class methods, which are forwarded to the
      #     shared singleton instance of Datadog::Statsd. You can also instantiate this class in
      #     case you want to reuse either the metric name, or tags, specify AB test semantics, or
      #     override the default sample rate while sending a metric to Datadog.
      #
      # @example
      #   # Increment the COUNT-type metric called "corp-inc.emails.sent" with the given tags.
      #
      #   Datadog::Statsd::Schema::Emitter.increment('emails.sent', tags: {..}, by: 2)
      #
      #   # The same thing, but reuses tags and metric name from the #new() method:
      #   tracker = Datadog::Statsd::Schema::Emitter.new('emails.sent', tags: {..})
      #   tracker.increment(by: 2)
      #   tracker.decrement
      #
      #   # Send a COUNT type metric from the SessionsController, setting the "emitter" tag,
      #   # and adding a tag if the logged in user is premium, and override the default
      #   # rate. Please note this does not create a new Statsd Connection — this only creates
      #   # a wrapper instance that reuses the tags and the sample rate from its initialization
      #
      #   tracker = Datadog::Statsd::Schema::Emitter.new(SessionsController, tags: { premium: true }, sample_rate: 0.5)
      #   tracker.increment('emails.sent', by: 2)
      #
      # This class also supports AB testing.
      # To track AB Test you can set the following tags using one of the two shown methods:
      #
      #   1. (Verbose method):
      #   abtest_tracker = Datadog::Statsd::Schema::Emitter.new(self, tags: {
      #     ab_test_name: "login_test_2025",
      #     ab_test_group: "control"
      #   })
      #   abtest_tracker.increment('users.loogged_in')
      #
      #   2. (Shortcut method): or use the following shortcut, which can also be used
      #      with the individual #increment, #decrement, #gauge, #histogram, #distribution methods.
      #
      #   # This creates a new wrapper instance that will always send the one metric "user.logged_in",
      #   # with the given tags and AB test name, althoug ab_test group and name can be overridden
      #   # by the individual calls to Statsd functions such as #increment, etc.

      #   login_statsd = Datadog::Statsd::Schema::Emitter.new('users.logged_in', ;ab_test: { "login_test_2025" => "control" })
      #   login_statsd.increment(ab_test: { "login_test_2025" => "variant_01" })
      #
      class Emitter
        MUTEX ||= Mutex.new

        DEFAULT_HOST = '127.0.0.1'
        DEFAULT_PORT = 8125
        DEFAULT_NAMESPACE = nil
        DEFAULT_ARGUMENTS = { delay_serialization: true }
        DEFAULT_SAMPLE_RATE = 1.0

        # @description This class is a wrapper around the Datadog::Statsd class. It provides a
        #     simple interface for sending metrics to Datadog. It also supports AB testing.
        #
        #     @see Datadog::Statsd::Schema::Emitter.new for more details.
        #
        class << self
          attr_reader :datadog_statsd

          # @return [Datadog::Statsd, NilClass] The Datadog Statsd client instance or nil if not
          #     currently connected.
          def statsd
            unless defined?(@datadog_statsd)
              @datadog_statsd = connect
            end
            @datadog_statsd
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

        attr_reader :tags, :ab_test, :sample_rate, :metric

        # @description You can create instances of this class and use the instance to emit custom
        #     metrics. You may want to do this, instead of using the class methods directly, for
        #     two reasons:
        #
        #        1. You want to send metrics from several places in the codebase, but have them
        #           share the "emitter" tag (which i.e. defines the source, a class, or object)
        #           emitting the metric, or any other tags for that matter.
        #
        #        2. You want to send metrics with a different sample rate than the defaults.
        #
        #     In both cases, you can create an instance of this class and use it to emit metrics.
        #
        #     NAMING METRICS:
        #     ================================
        #     Please remember that naming *IS* important. Good naming is self-documenting, easy
        #     to slice the data by, and easy to understand and analyze. Keep the number of unique
        #     metric names down, number of tags down, and the number of possible tag values
        #     should always be finite. If in doubt, set a tag, instead of creating a new metric.
        #
        # @example Tracking email delivery with statsd. Imagine that we want to track email delivery.
        #     But we have many types of emails that we send. Instead of creating new metric for
        #     each new email type, use the tag "email_type" to specify what type of email it is.
        #     Keep metric name list short, eg: "emails.queued", "emails.sent", "emails.delivered"
        #     are good metrics as they define a distinctly unique events. However, should you want
        #     to differentiate between different types of emails, you could theoretically do the
        #     following: (BAD EXAMPLE, DO NOT FOLLOW) — "emails.sent.welcome", "emails.sent.payment".
        #     But this example conflates two distinct events into a single metric. Instead, we should
        #     use tags to set event properties, such as what type of email that is.
        #
        #     @welcome_statsd = Datadog::Statsd::Schema::Emitter.new(self, tags: { email_type: 'welcome' })
        #
        #     @welcome_statsd.increment('emails.queued')
        #     @welcome_statsd.increment('emails.delivered', by: count)
        #     @welcome_statsd.gauge('emails.queue.size', Queue.size)
        #
        # @param emitter [String, Symbol, Module, Class] Attach a context to the source emitting the metric.
        #     This can be a "self", a string, a symbol, a module, or a class. It's a shorthand
        #     for adding the tag "emitter:#{emitter}" to the metric. When you pass a "self" or
        #     class/module, the value will be downcased and underscored, passing self (an instance of
        #     Users::SessionsController) will tag this metric with "emitter:users.sessions_controller".
        #
        # @param metric [String] The (optional) name of the metric to track. WARNING: if you set the
        #     metric name in the constructor, plaase make sure you send the data for the metric using
        #     consistent or compatible methods. For example, once you send INCREMENT(), you can no longer
        #     send the same metric with GAUGE(), or HISTOGRAM(), but you CAN use DECREMENT().
        #
        # @param tags [Hash] The (optional) additional tags to add to the metric sent with this wrapper.
        # @param ab_test [Hash] The (optional) AB test name => group mapping send as the tags ab_test_name/group.
        # @param sample_rate [Float] The (optional) override the default sample rate for this emitters/metric.
        #
        # @example
        #   Datadog::Statsd::Schema::Emitter.new(self).increment('emails.sent', by: 2)
        #   Datadog::Statsd::Schema::Emitter.new(nil, ab_test: { 'login_test_2025' => 'control' }).increment('users.logged_in')
        #
        #   Datadog::Statsd::Schema::Emitter.new(SessionsController).gauge('users.on.site', 100)
        #   Datadog::Statsd::Schema::Emitter.new(SessionsController, metric: 'users.on.site').gauge(100)
        #
        def initialize(emitter = nil, metric: nil, tags: nil, ab_test: nil, sample_rate: nil)
          if emitter.nil? && metric.nil? && tags.nil? && ab_test.nil? && sample_rate.nil?
            raise ArgumentError,
                  'Statsd::Schema::Emitter: use class methods if you are passing nothing to the constructor.'
          end

          @sample_rate = sample_rate || 1.0
          @tags = tags || nil
          @tags.merge!(self.class.global_tags.to_h) if self.class.global_tags.present?

          @ab_test = ab_test || {}
          @metric = metric

          emitter =
            case emitter
            when String, Symbol
              emitter.to_s
            when Module, Class
              emitter.name
            else
              emitter&.class&.name
            end

          emitter = nil if emitter == 'Object'
          emitter = emitter&.gsub('::', '.')&.underscore&.downcase

          return unless emitter

          @tags ||= {}
          @tags[:emitter] = emitter
        end

        def method_missing(m, *args, **opts, &)
          args, opts = normalize_arguments(*args, **opts)
          if ENV.fetch('DATADOG_DEBUG', false)
            warn "<CUSTOM METRIC to STATSD>: #{self}->#{m}(#{args.join(', ')}, #{opts.inspect})"
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

        delegate :flush, to: :class

        delegate :statsd, to: :class
      end
    end
  end
end
