[![RSpec and Rubocop](https://github.com/kigster/datadog-statsd-schema/actions/workflows/ruby.yml/badge.svg)](https://github.com/kigster/datadog-statsd-schema/actions/workflows/ruby.yml)

# Datadog::Statsd::Schema

This is a wrapper around  [dogstatsd-ruby](https://github.com/DataDog/dogstatsd-ruby) gem that sends custom metrics via StatsD, with an added layer of various features for Statsd Power users. 

The gem features:

 * Class `Datadog::Statsd::Emitter` that wraps an instance of `Datadog::Statsd`.
 * Sends tags that are the result of a merge of
   * global tags configured, 
   * any schema-based tags associated with the metric and its namespace, 
   * tags provided to the `Emitter.new` 
   * and finally, the specific tags provided with each call to `#increment` or `#gauge` etc.

 * Declarative schema for permitted metric names, their metric types, the tags required and allowed to be associated with the metric, as well as the tag values validation based on a flexible validation strategy.
 * Flexible validation strategy: `:strict` raises an exception, `:warn` prints a warning to STDERR, `:drop` skips invalid metric send silently, and `:off` turns off validation.

This approach helps keeping custom metrics sent to Datadog organized and adhere to the predefined schema. 

Datadog counts as a single custom metric any named datapoint (eg, "metric name") with a unique combination of tags that are sent to Datadog. In other words only the tag combinations that are actually received by Datadog count towards a custom metric, not all theoretically possible. 

Even still, it's easy to accidentally create a tag with a unique ID, such as `{ user_id: current_user.id }` which would result in a potentially infinite number of custom metrics, as each unique user would add a new dimension (and thus, new custom metric). 

By utilizing the schema you can prevent runaway metric explosion, design the metrics associated with each feature ahead of coding, and be sure that no other tag names or values are ever coming through. This helps keep custom metrics under control, and helps you apply a "design-first, code later" approach.

> [!TIP]
> We invite you to explore some of the provided [examples](./examples/README.md) which can be run from project's root, and are described in the linked README.

## Introduction

### The Problem with `Datadog::Statsd`

The gem [dogstatsd-ruby](https://github.com/DataDog/dogstatsd-ruby) acts as a proxy to Statsd daemon, and allows sending any number of metrics and associated tags to Datadog.

The gem does not allow constraining the tags or tag values, or even metric names and types. Whatever you put into the method call "goes":

```ruby

$statsd.increment('my.foosball.score', by: 3,
  tags: { 
    match_against: %w[jon bella ravi], 
    high_score: 34,
    played_at: "2025-06-01 12:24pm"
  }
)
```

> [!CAUTION]
> This is a completely valid use of Statsd, however it has a problem: each tag may have infinite number of possible values, and therefore will result in an explosion of custom metrics that will be largely useless.

> [!IMPORTANT]   
> Tagging is most useful **when tags are defined as discrete dimensions with a finate set of values. Then the metric submitted can be filtered by, group by, shown the top N tag values, etc of this metric along the tag's axis.**. So tagging consistently, correctly, and applying the minimum number of tags and tag values possible to achieve the required granularty is the balancing act of the metric designer. This gem is a tool necessary in designing the metrics and their tags ahead of time, not as an after-thought.

### Using the `Emitter` 

While the class `Datadog::Statsd::Emitter` provides class-level methods, such as `#increment`, etc, you might as well us `Datadog::Statsd` directly if you prefer class methods. 

You can access the power of this gem only when you instantiate one or more `Emitter` class (multiple emitters can all shares to the same `$statsd` sender process). Using `Emitter` instances adds a number of features and powerful shortcuts: 

#### Schema-Less Usage

Even if you do not pass the schema argument to the emitter, it will act as a wrapper around `Datadog::Statsd` instance and provide a useful feature: it will merge the globally defined tags, with the tags passed to `Emmitter` constructor, and the local tags passed to individual methods such as `#gauge` or `#distribution`. It will automatically append the `emitter: "string"` tag, where the "string" is the first argument to the constuctor, often `self` to indicate the place in code where `Emitter` was created.

#### Using Schemas

But the true power of this gem comes after you declare one or more schemas with namespace, metrics (and metric types) and tags, and passing the schema to the `Emitter` as a constructor argument. 

In that case every metric send will be validated against the schema.

# Usage

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

## Defining Schema 

Below is an example of configuring the gem by creating a schema using the provided DSL. This can be a single global schema or assigned to a specific Statsd Sender, although you can have any number of Senders of type `Datadog::Statsd::Emitter` that map to a new connection and new defaults.

### Example 1. Tracking the Results of a Marathon Race

In this example we'll be emitting various tags to compute number of people participating in a race, number of people who finished the race, and the distribution of the finishing times by the participants.

This first section is the "boilerplate" initialization that you'd likely need in your initializer for this gem:

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
```

Above, we created a real `Datadog:Statsd` sender, and then created a general configuration providing some global tags.

Next, we are going to define the schema for the metrics and tags we'd like to receive:

```ruby
# Now we'll create a Schema using the provided Schema DSL:
# equivalent to Datadog::Statsd::Schema.new
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
```

The schema is defined using a DSL that can use keywords such as `namespace`, `tags`, `tag`, `counter`, `gauge`, `distribution`, etc.

Now, we are going to create the emitter constrained by this schema:

```ruby
# Equivalent to Datadog::Statsd::Emitter.new()
my_sender = Datadog.emitter(
  metric: 'marathon',
  schema: schema,
  validation_mode: :strict,
  tags: { marathon_type: "full", course: "san-francisco" }
)

my_sender.increment('started.total', by: 43579) # register all participants at start
# time passes, first runners start to arrive
my_sender.increment('finished.total') # register one at a time
my_sender.distribution('finished.duration', 33.21, tags: { sponsorship: 'nike' })
... 
my_sender.increment('finished.total')
my_sender.distribution('finished.duration', 35.09, tags: { sponsorship: "redbull" })
```

In this case, the schema will validate that the metrics are named `marathon.finished.total` and `marathon.finished.duration`, and that their tags are appropriately defined.

And if we try to send metrics that are not valid, or tag values that have not been registered (like `course: "austin"`) we get the following errors, as shown on this screenshot from running the provided examples:

![invalid](https://raw.githubusercontent.com/kigster/datadog-statsd-schema/refs/heads/main/examples/schema_emitter.png)

In the next example, we initialize emitter with the metric `marathon.finished`, which indicates that we are only going to be sending the finishing data with this emitter. Note how the first argument we pass to `increment()` and `distribution()` are just words like `total` and `duration`, which are appended to `marathon.finished`.

```ruby
finish_sender = Datadog.emitter(
  schema: schema,
  validation_mode: :warn,
  metric: "marathon.finished", 
  tags: { marathon_type: "full", course: "san-francisco" }
)
finish.increment("total")
finish.distribution("duration", 34)
```

The above code will transmit the following metric, with the following tags:

```ruby
$statsd.increment(
  "marathon.finished.total", 
  tags: { 
    marathon_type: :full, 
    course: "san-francisco", 
    env: "produiction", 
    arch: "x86_64", 
    version: "a6a6e7f" 
  }
)

$statsd.distribution(
  "marathon.finished.duration", 
  34,
  tags: { 
    marathon_type: :full, 
    course: "san-francisco",
    env: "produiction", 
    arch: "x86_64", 
    version: "a6a6e7f" 
  }
)
```

### Validation Mode

There are four validation modes you can pass to an emitter to accompany a schema:

1. `:strict` — raise an exception when anything is out of the ordinary is passed
2. `:warn` — print to stderr and continue 
3. `:drop` — drop this metric
4. `:off` — no validation, as if schema was not even passed.

### Example 2. Tracking Web Performance

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
  metric: "web.request", 
  tags: { billing_plan: :premium, logged_in: :logged_in }
)

my_sender.increment('total', tags: { uri: '/home/settings', method: :get } ) 
my_sender.distribution('duration', tags: { uri: '/home/settings', method: :get } ) 

my_sender.increment('total', tags: { uri: '/app/calendar', method: :post} )
my_sender.distribution('duration', tags: { uri: '/app/calendar', method: :post } )
```
      
The above code will send two metrics: `web.request.total` as a counter, tagged with: `{ billing_plan: :premium, logged_in: :logged_in, uri: '/home/settings' }` and the second time for the `uri: '/app/calendar'`. 

## The `Emitter` Adapter

The `Emitter` class can be used to send metrics either by using the class methods or instance methods.

### `Datadog::Statsd::Emitter` Instances

You can create any number of instances of this class and use it to emit custom metrics. You get the following benefits:

 1. You want to send metrics from several places in the codebase, but have them either share the "emitter" tag (which i.e. defines the source, a class, or object) emitting the metric, or have a distinct "emitter" tag defining the place in code the metric was generated. 

 2. You can pass the metric's partial name to the constructor, so that calls to statsd methods only pass the last section of the metric name, eg `marathon.finished` could be the metric name, and `total` could be the first argument to `#increment('total')` function, resulting in the metric `marathon.finished.total` to be incremented.

 3. Any tags you pass in the constructor to the `Emitter` will be automatically added to every send call from this emitter (after being merged with the global tags, and the local tags passed to the method).

 4. Given a schema, all metrics, tags and tag values will be validated against a predefined configuration.

 5. You want to send a particular metric with a different sample rate than the default rate.

### `Datadog::Statsd::Emitter` Class Methods

You can use `Emitter`'s class methods to send metrics, but we don't recommend it as it's not much different than using `$statsd` directly. Class methods do not support tag merging or schema validation.

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

As you can see, the API is identical to `Datadog::Statsd`. The main difference is that, if you provide a schema argument, the metric `marathon.started.total` must be pre-declared using the schema DSL language. In addition, the metric type ("count") and all of the tags and their possible values must be predeclared in the schema. Schema does support opening up a tag to any number of values, but that is not recommended.

### Naming Metrics

Please remember that naming *IS* important. Good naming is self-documenting, easy to slice the data by, and easy to understand and analyze. Keep the number of unique metric names down, number of tags down, and the number of possible tag values should always be finite. If in doubt, set a tag, instead of creating a new metric.

### Example 3. Tracking email delivery 

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

#### What's the Emitter First Constructor Arguments?

The first argument to the `Emitter.new("emitter-name")` or `Datadog.emitter("emitter-name")` (those are equivalent) is an object or a string or a class that's converted to a tag called `emitter`. This is the source class or object that sent the metric. The same mwtric may come from various places in your code, and `emitter` tag allows you to differentiate between them.

Subsequent arguments are hash arguments. 

 * `metric` — The (optional) name of the metric to track. If set to, eg. `emails`, then any subsequent method sending metric will prepend `emails.` to it, for example:

```ruby
emitter.increment('sent.total', by: 3)
```

Will actually increment the metric `emails.sent.total`.

### More Examples


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
