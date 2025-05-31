[![RSpec and Rubocop](https://github.com/kigster/datadog-statsd-schema/actions/workflows/ruby.yml/badge.svg)](https://github.com/kigster/datadog-statsd-schema/actions/workflows/ruby.yml)

# Datadog::Statsd::Schema

## Introduction

This is an extension to gem [dogstatsd-ruby](https://github.com/DataDog/dogstatsd-ruby) which enhances the original with a robust schema definition for both the custom metrics being sent, and the tags allowed (or required) to attach to the metric. 

There are two interfaces to `Datadog::Statsd` instance — you can use the class methods of `Datadog::Statsd::Schema`, and pass the typical statsd methods. But you can also use an instance of this class, which adds a number of features and powerful shortcuts.

### Class Methods

This is the most straightforward way of using this gem. You can just pass your metric names and tags to the standard operations on Statsd, just like so:

```ruby
  Datadog::Statsd::Schema.increment(
    'marathon.started', 
    by: 7, 
    tags: { 
        course: "sf-marathon", 
        length: 26.212, 
        units: "miles" 
    },
    schema: ....
  )
```

As you can see, the API is identical to that of `Datadog::Statsd`. The main difference is that, if you provide a schema argument, then the metric `marathon.started` must be pre-declared using the schema DSL language. In addition, metric type ("count"), and all of the tags and their possible values must be predeclared in the schema. Schema does support opening up a tag to any number of values, but that is not recommended.

So let's look at a more elaborate use-case.

### Defining Schema 

Below is an example where we configure the gem by creating a schema using the provided DSL. This can be a single global schema or assigned to a specific Statsd Sender, although you can have any number of Senders of type `Datadog::Statsd::Schema::Emitter` that map to a new connection and new defaults.

```ruby
  require 'datadog/statsd'
  require 'etc'
  require 'git'

  $statsd = ::Datadog::Statsd.new(
    'localhost', 8125, 
    delay_serialization: true
  )
  
  Datadog::Statsd::Schema.configure do |config|
    config.statsd = $statsd

    # This configures the global tags that will be attached to all methods
    config.tags = { 
      env: "development",
      arch: Etc.uname[:machine],
      version: Git.open('.').object('HEAD').sha
    }

    config.schema = Datadog::Statsd::Schema.new do
      # Transformers can be attached to the tags, and apply before the tags are submitted
      # or validated.
      transformers do
        underscore: ->(text) { text.underscore },
        downcase: ->(text) { text.downcase }
      end

      namespace :marathon do
        tags do
          tag :course, values: ["san francisco", "boston", "new york"]
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
  end

  my_sender = Datadog::Statsd::Schema::Emitter.new(
    prefix: "marathon", 
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

You can provide a more specific prefix, which would then be unnecessary when declaring the metric name. In  both cases, the Schema will validate that the metric named
`marathonfinished.total` and `marathon.finished.duration` are properly defined.

```ruby
  finish_sender = Datadog::Statsd::Schema::Emitter.new(
    prefix: "marathon.finished", 
    tags: { marathon_type: :full, course: "san-francisco" }
  )
  finish.increment('total')
  finish.distribution('duration', 34)
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
  # It's equivalent to *Datadog::Statsd::Schema::Emitter.new*
  traffic_monitor = Datadog.emitter(
    self,
    prefix: "web.request", 
    tags: { billing_plan: :premium, logged_in: :logged_in }
  )

  my_sender.increment('total', uri: '/home/settings') 
  my_sender.distribution('duration', uri: '/home/settings') 

  my_sender.increment('total', uri: '/app/calendar')
  my_sender.distribution('duration', uri: '/app/calendar')
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
