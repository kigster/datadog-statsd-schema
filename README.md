[![RSpec and Rubocop](https://github.com/kigster/datadog-statsd-schema/actions/workflows/ruby.yml/badge.svg)](https://github.com/kigster/datadog-statsd-schema/actions/workflows/ruby.yml)

# Datadog::Statsd::Schema

This is a wrapper around  [dogstatsd-ruby](https://github.com/DataDog/dogstatsd-ruby) gem that sends custom metrics via StatsD, with additional layer of validation based on a configurable schemas. Schemas can validate allowed metric names, associated tag and tag values. This approach can guide an organization towards a clear declarative approach to metrics and their tags, and then emitting them from within the application with the insurance that any invalid value would raise an exception. 

We invite you to explore some of the provided [examples](./examples/README.md) which can be run from project's root, and are described in the linked README.

## Introduction

This is an extension to gem [dogstatsd-ruby](https://github.com/DataDog/dogstatsd-ruby) which enhances the original with a robust schema definition for both the custom metrics being sent, and the tags allowed (or required) to attach to the metric. 

There are several interfaces to `Datadog::Statsd` instance — you can use the class methods of `Datadog::Statsd::Emitter`, and pass the typical statsd methods. But you can also use an instance of this class, which adds a number of features and powerful shortcuts. 

If you do not pass the schema argument to the emitter, it will act as a wrapper around `Datadog::Statsd` instance: it will merge the global and local tags together, it will concatenate metric names together, so it's quite useful on it' on.

But the real power comes from defining a Schema of metrics and tags, and providing the schema to the Emitter as a constructor argument. In that case every metric send will be validated against the schema.
 
## Metric Types

> For more information about the metrics, please see the [Datadog Documentation](https://docs.datadoghq.com/metrics/custom_metrics/dogstatsd_metrics_submission/?tab=ruby).

There are 5 total metric types you can send with Statsd, and it's important to understand the differences:

* `COUNT` (eg, `Datadog::Statsd::Emitter.increment('emails.sent', by: 2)`)
* `GAUGE` (eg, `Datadog::Statsd::Emitter.gauge('users.on.site', 100)`)
* `HISTOGRAM` (eg, `Datadog::Statsd::Emitter.histogram('page.load.time', 100)`)
* `DISTRIBUTION` (eg,`Datadog::Statsd::Emitter.distribution('page.load.time', 100)`)
* `SET` (eg, `Datadog::Statsd::Emitter.set('users.unique', '12345')`)

NOTE: that `HISTOGRAM` converts your metric into FIVE separate metrics (with suffixes .`max`, .`median`, `avg`, .`count`, `p95`), while `DISTRIBUTION` explodes into TEN separate metrics (see the documentation). Do NOT use SET unless you know what you are doing.

You can send metrics via class methods of `Datadog::Statsd::Emitter`, or by instantiating the class.

## Sending Metrics 

### Class Methods

This is the most straightforward way of using this gem. You can just pass your metric names and tags to the standard operations on Statsd, just like so:

```ruby
  require 'datadog/statsd'
  require 'datadog/statsd/schema'

  Datadog::Statsd::Emitter.increment(
    'marathon.started.total', 
    by: 7, 
    tags: { 
        course: "sf-marathon", 
        length: 26.212, 
        units: "miles" 
    },
    schema: ....
  )
```

As you can see, the API is identical to that of `Datadog::Statsd`. The main difference is that, if you provide a schema argument, then the metric `marathon.started.total` must be pre-declared using the schema DSL language. In addition, metric type ("count"), and all of the tags and their possible values must be predeclared in the schema. Schema does support opening up a tag to any number of values, but that is not recommended.

So let's look at a more elaborate use-case.

### Defining Schema 

Below is an example where we configure the gem by creating a schema using the provided DSL. This can be a single global schema or assigned to a specific Statsd Sender, although you can have any number of Senders of type `Datadog::Statsd::Emitter` that map to a new connection and new defaults.

```ruby
  require 'etc'
  require 'git'

  require 'datadog/statsd'
  require 'datadog/statsd/schema'

  # Define the global statsd instance that we'll use to send data through
  $statsd = ::Datadog::Statsd.new(
    'localhost', 8125, 
    delay_serialization: true
  )

  # Configure the schema with global tags and the above-created Statsd instance
  Datadog::Statsd::Schema.configure do |config|
    # This configures the global tags that will be attached to all methods
    config.tags = { 
      env: "development",
      arch: Etc.uname[:machine],
      version: Git.open('.').object('HEAD').sha
    }
    
    config.statsd = $statsd
  end

  # Now we'll create a Schema using the provided Schema DSL:
  schema = Datadog.schema do
    # Transformers can be attached to the tags, and applied before the tags are submitted
    # or validated.
    transformers do
      underscore: ->(text) { text.underscore },
      downcase: ->(text) { text.downcase }
    end

    namespace :marathon do
      tags do
        tag :course, 
            values: ["san francisco", "boston", "new york"],         
            transform: %i[downcase underscore],

        tag :marathon_type, values: %w[half full]
        tag :status, values: %w[finished no-show incomplete]
        tag :sponsorship, values: %w[nike cocacola redbull]
      end

      metrics do 
        # This defines a single metric "marathon.started.total"
        namespace :started do
          counter :total do
            description "Incrementing - the total number of people who were registered for this marathon"
            tags required: %i[ course marathon_type ],
                  allowed:  %i[ sponsorship ]
          end
        end

        # defines two metrics: a counter metric named "marathon.finished.total" and
        # a distribution metric "marathon.finished.duration"
        namespace :finished do
          counter :total, inherit_tags: "marathon.started.total",
            description "The number of people who finished a given marathon"
            tags required: %i[ status ]
          end

          distribution :duration, units: "minutes", inherit_tags: "marathon.finished.count" do
            description "The distribution of all finish times registered."
          end
        end   
      end
    end
  end

  my_sender = Datadog.emitter(
    schema: schema,
    tags: { marathon_type: :full, course: "san-francisco" }
  )

  my_sender.increment('started.total', by: 43579) # register all participants at start
  # time passes, first runners start to arrive
  my_sender.increment('finished.total') # register one at a time
  my_sender.distribution('finished.duration', 33.21, tags: { sponsorship: 'nike' })
  ... 
  my_sender.increment('finished.total')
  my_sender.distribution('finished.duration', 35.09, tags: { sponsorship: "redbull" })
```

You can provide a more specific prefix, which would be unnecessary when declaring the metric name. In  both cases, the Schema will validate that the metrics named `marathonfinished.total` and `marathon.finished.duration` are appropriately defined.

```ruby
  finish_sender = Datadog.emitter(
    metric: "marathon.finished", 
    tags: { marathon_type: :full, course: "san-francisco" }
  )
  finish.increment("total")
  finish.distribution("duration", 34)
```

The above code will transmit the following metric, with the following tags:

```ruby
$statsd.increment(
  "marathon.finished.total", 
  tags: { marathon:type: :full, course: "san-francisco" }
)

$statsd.distribution(
  "marathon.finished.duration", 
  tags: { marathon:type: :full, course: "san-francisco" }
)
```

### An Example Tracking Web Performance

```ruby
 Datadog::Statsd::Schema.configure do |config|
    config.statsd = $statsd
    config.schema = Datadog::Statsd::Schema.new do
      namespace "web" do
        namespace "request" do
          tags do
            tag :uri,
                values: %r{.*}

            tag :logged_in,
                values: %w[logged_in logged_out]

            tag :billing_plan,
                values: %w[premium trial free]

            tag :controller, 
                values: %r{[a-z.]*}, 
                transform: [ :underscore, :downcase ]

            tag :action, 
                values: %r{[a-z.]*}, 
                transform: [ :underscore, :downcase ]

            tag :method, 
                values: %i[get post put patch delete head options trace connect], 
                transform: [ :downcase ]

            tag :status_code, 
                type: :integer, 
                validate: ->(code) { (100..599).include?(code) }
          end
          
          metrics do
            # This distribution allows tracking of the latency of the request.
            distribution :duration do
              description "HTTP request processing time in milliseconds"
              tags allowed: %w[controller action method status_code region]
                  required: %w[controller]
            end
          
            # This counter allows tracking the frequency of each controller/action
            counter :total, inherit_tags: :duration do
              description "Total number of requests received"
            end
          end
        end
      end
    end
  end
```


Let's say this monitor only tracks requests from logged in premium users,  then you can provide those tags here, and they will be sent together with individual invocations:

```ruby
  # We'll use the shorthand version to create this Emitter.
  # It's equivalent to *Datadog::Statsd::Emitter.new*
  traffic_monitor = Datadog.emitter(
    self,
    prefix: "web.request", 
    tags: { billing_plan: :premium, logged_in: :logged_in }
  )

  my_sender.increment('total', tags: { uri: '/home/settings', method: :get } ) 
  my_sender.distribution('duration', tags: { uri: '/home/settings', method: :get } ) 

  my_sender.increment('total', tags: { uri: '/app/calendar', method: :post} )
  my_sender.distribution('duration', tags: { uri: '/app/calendar', method: :post } )
```
      
The above code will send two metrics: `web.request.total` as a counter, tagged with: `{ billing_plan: :premium, logged_in: :logged_in, uri: '/home/settings' }` and the second time for the `uri: '/app/calendar'`. 

### Emitter

You can create instances of this class and use the instance to emit custom metrics. You may want to do this, instead of using the class methods directly, for two reasons:

 1. You want to send metrics from several places in the codebase, but have them share the "emitter" tag (which i.e. defines the source, a class, or object)emitting the metric, or any other tags for that matter.

 2. You want to send metrics with a different sample rate than the defaults.

In both cases, you can create an instance of this class and use it to emit metrics.

#### Naming Metrics

Please remember that naming *IS* important. Good naming is self-documenting, easy to slice the data by, and easy to understand and analyze. Keep the number of unique metric names down, number of tags down, and the number of possible tag values should always be finite. If in doubt, set a tag, instead of creating a new metric.

#### Example — Tracking email delivery 

Imagine that we want to track email delivery. But we have many types of emails that we send. Instead of creating new metric for each new email type, use the tag "email_type" to specify what type of email it is.

Keep metric name list short, eg: "emails.queued", "emails.sent", "emails.delivered" are good metrics as they define a distinctly unique events. However, should you want to differentiate between different types of emails, you could theoretically do the following: (BAD EXAMPLE, DO NOT FOLLOW) — "emails.sent.welcome", "emails.sent.payment". But this example conflates two distinct events into a single metric. Instead, we should use tags to set event properties, such as what type of email that is.

```ruby

    emails_emitter = Datadog.emitter(
      self, 
      metric: 'emails'
    )

    emails_emitter.increment('queued.total')
    emails_emitter.increment('delivered.total', by: count)
    emails_emitter.gauge('queue.size', EmailQueue.size)
```

#### What's the Emitter Constructor Arguments?

The first argument to the `Emitter.new()` or `Datadog.emitter()` (those are equivalent) is an object or a string or a class that's converted to a tag called `emitter`. This is the source class or object that sent the metric. The same mwtric may come from various places in your code, and `emitter` tag allows you to differentiate between them.

Subsequent arguments are hash arguments. 

 * `metric` — The (optional) name of the metric prefix to track. If set to, eg. `emails`, then any subsequent method sending metric will prepend `emails.` to it, for example:

```ruby
emitter.increment('sent.total', by: 3)
```

Will actually increment the metric `emails.sent.total`.

#### Other Examples

```ruby

  Datadog.emitter(self)
    .increment('emails.sent', by: 2)

  Datadog.emitter(ab_test: { 'login_test_2025' => 'control' })
    .increment('users.logged_in')
  # => tags: { ab_test_name: 'login_test_2025', 
  #            ab_test_group: 'control' } 

  Datadog.emitter(SessionsController, metric: 'users')
     .gauge('logged_in', 100)

  sessions = Datadog.emitter(SessionsController, metric: 'users')
  # => tags: { emitter: "sessions_controller" }
  sessions.gauge('active', 100)
  sessions.distribution('active.total', 114)
```

## Installation


```bash
bundle add datadog-statsd-schema
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install datadog-statsd-schema
```

## Usage

1. Define your metrics and tagging schema
2. Create as many "emitters" as necessary and start sending!

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/kigster/datadog-statsd-schema](https://github.com/kigster/datadog-statsd-schema)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
