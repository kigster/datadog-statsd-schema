[![RSpec and Rubocop](https://github.com/kigster/datadog-statsd-schema/actions/workflows/ruby.yml/badge.svg)](https://github.com/kigster/datadog-statsd-schema/actions/workflows/ruby.yml)

# Datadog::Statsd::Schema

## Stop the Metric Madness (And Save Your Budget) 💸

*"With great StatsD power comes great billing responsibility"* 

Every engineering team starts the same way with [Datadog custom metrics](https://docs.datadoghq.com/metrics/custom_metrics/dogstatsd_metrics_submission/?tab=ruby): a few innocent calls to `statsd.increment('user.signup')`, maybe a `statsd.gauge('queue.size', 42)`. Life is good. Metrics are flowing. Dashboards are pretty.

Then reality hits. Your Datadog bill explodes 🚀 because:

- **Marketing** added `statsd.increment('clicks', tags: { campaign_id: campaign.id })` across 10,000 campaigns
- **DevOps** thought `statsd.gauge('memory', tags: { container_id: container.uuid })` was a great idea  
- **Frontend** started tracking `statsd.timing('page.load', tags: { user_id: current_user.id })` for 2 million users
- **Everyone** has their own creative naming conventions: `user_signups`, `user.sign.ups`, `users::signups`, `Users.Signups`

**Congratulations!** 🎉 You now have 50,000+ custom metrics, each [costing real money](https://docs.datadoghq.com/account_management/billing/custom_metrics/), most providing zero actionable insights.

This gem exists to prevent that chaos (and save your engineering budget).

## The Solution: Schema-Driven Metrics

This gem wraps [dogstatsd-ruby](https://github.com/DataDog/dogstatsd-ruby) with two superpowers:

1. **🏷️ Intelligent Tag Merging** - Even without schemas, get consistent tagging across your application
2. **📋 Schema Validation** - Define your metrics upfront, validate everything, prevent metric explosion

Let's see how this works, starting simple and building up...

## Quick Start: Better Tags Without Schemas

Even before you define schemas, the `Emitter` class immediately improves your metrics with intelligent tag merging:

```ruby
require 'datadog/statsd/schema'

# Configure global tags that apply to ALL metrics
Datadog::Statsd::Schema.configure do |config|
  config.tags = { env: 'production', service: 'web-app', version: '1.2.3' }
  config.statsd = Datadog::Statsd.new('localhost', 8125)
end

# Create an emitter for your authentication service
auth_emitter = Datadog::Statsd::Emitter.new(
  'AuthService',                           # Automatically becomes emitter:auth_service tag
  tags: { feature: 'user_auth' }          # These tags go on every metric from this emitter
)

# Send a metric - watch the tag magic happen
auth_emitter.increment('login.success', tags: { method: 'oauth' })
```

**What actually gets sent to Datadog:**
```ruby
# Metric: auth_service.login.success
# Tags: { 
#   env: 'production',           # From global config
#   service: 'web-app',          # From global config  
#   version: '1.2.3',            # From global config
#   emitter: 'auth_service',     # Auto-generated from first argument
#   feature: 'user_auth',        # From emitter constructor
#   method: 'oauth'              # From method call
# }
```

**Tag Precedence (method tags win):**
- Method-level tags override emitter tags
- Emitter tags override global tags  
- Global tags are always included

This alone prevents the "different tag patterns everywhere" problem. But we're just getting started...

## Schema Power: Design Your Metrics, Then Code

Here's where this gem really shines. Instead of letting developers create metrics willy-nilly, you define them upfront:

```ruby
# Define what metrics you actually want
user_metrics_schema = Datadog::Statsd::Schema.new do
  namespace :users do
    # Define the tags you'll actually use (not infinite user_ids!)
    tags do
      tag :signup_method, values: %w[email oauth google github]
      tag :plan_type, values: %w[free premium enterprise]
      tag :feature_flag, values: %w[enabled disabled]
    end
    
    metrics do
      # Define exactly which metrics exist and their constraints
      counter :signups do
        description "New user registrations"
        tags required: [:signup_method], allowed: [:plan_type, :feature_flag]
      end
      
      gauge :active_sessions do
        description "Currently logged in users"  
        tags allowed: [:plan_type]
      end
    end
  end
end

# Create an emitter bound to this schema
user_emitter = Datadog::Statsd::Emitter.new(
  'UserService',
  schema: user_metrics_schema,
  validation_mode: :strict  # Explode on invalid metrics (good for development)
)

# This works - follows the schema
user_emitter.increment('signups', tags: { signup_method: 'oauth', plan_type: 'premium' })

# This explodes 💥 - 'facebook' not in allowed signup_method values
user_emitter.increment('signups', tags: { signup_method: 'facebook' })

# This explodes 💥 - 'user_registrations' metric doesn't exist in schema  
user_emitter.increment('user_registrations')

# This explodes 💥 - missing required tag signup_method
user_emitter.increment('signups', tags: { plan_type: 'free' })
```

**Schema validation catches:**
- ❌ Metrics that don't exist
- ❌ Wrong metric types (counter vs gauge vs distribution)  
- ❌ Missing required tags
- ❌ Invalid tag values
- ❌ Tags that aren't allowed on specific metrics

## Progressive Examples: Real-World Schemas

### E-commerce Application Metrics

```ruby
ecommerce_schema = Datadog::Statsd::Schema.new do
  # Global transformers for consistent naming
  transformers do
    underscore: ->(text) { text.underscore }
    downcase: ->(text) { text.downcase }
  end
  
  namespace :ecommerce do
    tags do
      # Finite set of product categories (not product IDs!)
      tag :category, values: %w[electronics clothing books home_garden]
      
      # Payment methods you actually support
      tag :payment_method, values: %w[credit_card paypal apple_pay]
      
      # Order status progression
      tag :status, values: %w[pending processing shipped delivered cancelled]
      
      # A/B test groups (not test IDs!)
      tag :checkout_flow, values: %w[single_page multi_step express]
    end
    
    namespace :orders do
      metrics do
        counter :created do
          description "New orders placed"
          tags required: [:category], allowed: [:payment_method, :checkout_flow]
        end
        
        counter :completed do
          description "Successfully processed orders"  
          inherit_tags: "ecommerce.orders.created"  # Reuse tag definition
          tags required: [:status]
        end
        
        distribution :value do
          description "Order value distribution in cents"
          units "cents"
          tags required: [:category], allowed: [:payment_method]
        end
        
        gauge :processing_queue_size do
          description "Orders waiting to be processed"
          # No tags - just a simple queue size metric
        end
      end
    end
    
    namespace :inventory do
      metrics do
        gauge :stock_level do
          description "Current inventory levels"
          tags required: [:category]
        end
        
        counter :restocked do
          description "Inventory replenishment events"
          tags required: [:category]
        end
      end
    end
  end
end

# Usage in your order processing service
order_processor = Datadog::Statsd::Emitter.new(
  'OrderProcessor',
  schema: ecommerce_schema,
  metric: 'ecommerce.orders',        # Prefix for all metrics from this emitter
  tags: { checkout_flow: 'single_page' }
)

# Process an order - clean, validated metrics
order_processor.increment('created', tags: { 
  category: 'electronics', 
  payment_method: 'credit_card' 
})

order_processor.distribution('value', 15_99, tags: { 
  category: 'electronics', 
  payment_method: 'credit_card' 
})

order_processor.gauge('processing_queue_size', 12)
```

### API Performance Monitoring

```ruby
api_schema = Datadog::Statsd::Schema.new do
  namespace :api do
    tags do
      # HTTP methods you actually handle
      tag :method, values: %w[GET POST PUT PATCH DELETE]
      
      # Standardized controller names (transformed to snake_case)
      tag :controller, 
          values: %r{^[a-z_]+$},           # Regex validation
          transform: [:underscore, :downcase]
      
      # Standard HTTP status code ranges
      tag :status_class, values: %w[2xx 3xx 4xx 5xx]
      tag :status_code, 
          type: :integer,
          validate: ->(code) { (100..599).include?(code) }
      
      # Feature flags for A/B testing
      tag :feature_version, values: %w[v1 v2 experimental]
    end
    
    namespace :requests do
      metrics do
        counter :total do
          description "Total API requests"
          tags required: [:method, :controller], 
               allowed: [:status_class, :feature_version]
        end
        
        distribution :duration do
          description "Request processing time"
          units "milliseconds"
          inherit_tags: "api.requests.total"
          tags required: [:status_code]
        end
        
        histogram :response_size do
          description "Response payload size distribution"
          units "bytes"
          tags required: [:method, :controller]
        end
      end
    end
    
    namespace :errors do
      metrics do
        counter :total do
          description "API errors by type"
          tags required: [:controller, :status_code]
        end
      end
    end
  end
end

# Usage in Rails controller concern
class ApplicationController < ActionController::Base
  before_action :setup_metrics
  after_action :track_request
  
  private
  
  def setup_metrics
    @api_metrics = Datadog::Statsd::Emitter.new(
      self.class.name,
      schema: api_schema, 
      metric: 'api',
      validation_mode: Rails.env.production? ? :warn : :strict
    )
  end
  
  def track_request
    controller_name = self.class.name.gsub('Controller', '').underscore
    
    @api_metrics.increment('requests.total', tags: {
      method: request.method,
      controller: controller_name,
      status_class: "#{response.status.to_s[0]}xx"
    })
    
    @api_metrics.distribution('requests.duration', 
      request_duration_ms, 
      tags: {
        method: request.method,
        controller: controller_name, 
        status_code: response.status
      }
    )
  end
end
```

## Validation Modes: From Development to Production

The gem supports different validation strategies for different environments:

```ruby
# Development: Explode on any schema violations
dev_emitter = Datadog::Statsd::Emitter.new(
  'MyService',
  schema: my_schema,
  validation_mode: :strict  # Raises exceptions
)

# Staging: Log warnings but continue  
staging_emitter = Datadog::Statsd::Emitter.new(
  'MyService', 
  schema: my_schema,
  validation_mode: :warn   # Prints to stderr, continues execution
)

# Production: Drop invalid metrics silently
prod_emitter = Datadog::Statsd::Emitter.new(
  'MyService',
  schema: my_schema, 
  validation_mode: :drop   # Silently drops invalid metrics
)

# Emergency: Turn off validation entirely
emergency_emitter = Datadog::Statsd::Emitter.new(
  'MyService',
  schema: my_schema,
  validation_mode: :off    # No validation at all
)
```

## Best Practices: Designing Schemas That Scale

### 🎯 Design Metrics Before Code

```ruby
# ✅ Good: Design session like this
session_schema = Datadog::Statsd::Schema.new do
  namespace :user_sessions do
    tags do
      tag :session_type, values: %w[web mobile api]
      tag :auth_method, values: %w[password oauth sso]
      tag :plan_tier, values: %w[free premium enterprise]
    end
    
    metrics do
      counter :started do
        description "User sessions initiated"
        tags required: [:session_type], allowed: [:auth_method, :plan_tier]
      end
      
      counter :ended do
        description "User sessions terminated" 
        tags required: [:session_type, :auth_method]
      end
      
      distribution :duration do
        description "How long sessions last"
        units "minutes"
        tags required: [:session_type]
      end
    end
  end
end

# ❌ Bad: Don't do this
statsd.increment('user_login', tags: { user_id: user.id })           # Infinite cardinality!
statsd.increment('session_start_web_premium_oauth')                  # Explosion of metric names!
statsd.gauge('active_users_on_mobile_free_plan_from_usa', 1000)     # Way too specific!
```

### 🏷️ Tag Strategy: Finite and Purposeful

```ruby
# ✅ Good: Finite tag values that enable grouping/filtering
tag :plan_type, values: %w[free premium enterprise]
tag :region, values: %w[us-east us-west eu-central ap-southeast]
tag :feature_flag, values: %w[enabled disabled control]

# ❌ Bad: Infinite or high-cardinality tags
tag :user_id                    # Millions of possible values!
tag :session_id                 # Unique every time!
tag :timestamp                  # Infinite values!
tag :request_path               # Thousands of unique URLs!
```

### 📊 Metric Types: Choose Wisely

```ruby
namespace :email_service do
  metrics do
    # ✅ Use counters for events that happen
    counter :sent do
      description "Emails successfully sent"
    end
    
    # ✅ Use gauges for current state/levels
    gauge :queue_size do
      description "Emails waiting to be sent"  
    end
    
    # ✅ Use distributions for value analysis (careful - creates 10 metrics!)
    distribution :delivery_time do
      description "Time from send to delivery"
      units "seconds"
    end
    
    # ⚠️ Use histograms sparingly (creates 5 metrics each)
    histogram :processing_time do
      description "Email processing duration" 
      units "milliseconds"
    end
    
    # ⚠️ Use sets very carefully (tracks unique values)
    set :unique_recipients do
      description "Unique email addresses receiving mail"
    end
  end
end
```

### 🔄 Schema Evolution: Plan for Change

```ruby
# ✅ Good: Use inherit_tags to reduce duplication
base_schema = Datadog::Statsd::Schema.new do
  namespace :payments do
    tags do
      tag :payment_method, values: %w[card bank_transfer crypto]
      tag :currency, values: %w[USD EUR GBP JPY]
      tag :region, values: %w[north_america europe asia]
    end
    
    metrics do
      counter :initiated do
        description "Payment attempts started"
        tags required: [:payment_method], allowed: [:currency, :region]
      end
      
      counter :completed do
        description "Successful payments"
        inherit_tags: "payments.initiated"  # Reuses the tag configuration
      end
      
      counter :failed do
        description "Failed payment attempts"
        inherit_tags: "payments.initiated"
        tags required: [:failure_reason]    # Add specific tags as needed
      end
    end
  end
end
```

### 🏗️ Namespace Organization

```ruby
# ✅ Good: Hierarchical organization by domain
app_schema = Datadog::Statsd::Schema.new do
  namespace :ecommerce do
    namespace :orders do
      # Order-related metrics
    end
    
    namespace :inventory do  
      # Stock and fulfillment metrics
    end
    
    namespace :payments do
      # Payment processing metrics
    end
  end
  
  namespace :infrastructure do
    namespace :database do
      # DB performance metrics  
    end
    
    namespace :cache do
      # Redis/Memcached metrics
    end
  end
end

# ❌ Bad: Flat namespace chaos
# orders.created
# orders_completed  
# order::cancelled
# INVENTORY_LOW
# db.query.time
# cache_hits
```

## Advanced Features

### Global Configuration

```ruby
# Set up global configuration in your initializer
Datadog::Statsd::Schema.configure do |config|
  # Global tags applied to ALL metrics
  config.tags = {
    env: Rails.env,
    service: 'web-app',
    version: ENV['GIT_SHA']&.first(7),
    datacenter: ENV['DATACENTER'] || 'us-east-1'
  }
  
  # The actual StatsD client
  config.statsd = Datadog::Statsd.new(
    ENV['STATSD_HOST'] || 'localhost',
    ENV['STATSD_PORT'] || 8125,
    namespace: ENV['STATSD_NAMESPACE'],
    tags: [], # Don't double-up tags here
    delay_serialization: true
  )
end
```

### Tag Transformers

```ruby
schema_with_transforms = Datadog::Statsd::Schema.new do
  transformers do
    underscore: ->(text) { text.underscore }
    downcase: ->(text) { text.downcase }  
    truncate: ->(text) { text.first(20) }
  end
  
  namespace :user_actions do
    tags do
      # Controller names get normalized automatically
      tag :controller,
          values: %r{^[a-z_]+$},
          transform: [:underscore, :downcase]  # Applied in order
      
      # Action names also get cleaned up  
      tag :action,
          values: %w[index show create update destroy],
          transform: [:downcase]
    end
  end
end

# "UserSettingsController" becomes "user_settings_controller"
# "CreateUser" becomes "create_user" 
```

### Complex Validation

```ruby
advanced_schema = Datadog::Statsd::Schema.new do
  namespace :financial do
    tags do
      # Custom validation with lambdas
      tag :amount_bucket,
          validate: ->(value) { %w[small medium large].include?(value) }
      
      # Regex validation for IDs
      tag :transaction_type,
          values: %r{^[A-Z]{2,4}_[0-9]{3}$}  # Like "AUTH_001", "REFUND_042"
      
      # Type validation  
      tag :user_segment,
          type: :integer,
          validate: ->(segment) { (1..10).include?(segment) }
    end
  end
end
```

### Loading Schemas from Files

```ruby
# config/metrics_schema.rb  
Datadog::Statsd::Schema.new do
  namespace :my_app do
    # ... schema definition
  end  
end

# In your application
schema = Datadog::Statsd::Schema.load_file('config/metrics_schema.rb')
```

## Installation

Add to your Gemfile:

```ruby
gem 'datadog-statsd-schema'
```

Or install directly:

```bash
gem install datadog-statsd-schema
```

## The Bottom Line

This gem transforms Datadog custom metrics from a "wild west" free-for-all into a disciplined, cost-effective observability strategy:

- **🎯 Intentional Metrics**: Define what you measure before you measure it
- **💰 Cost Control**: Prevent infinite cardinality and metric explosion  
- **🏷️ Consistent Tagging**: Global and hierarchical tag management
- **🔍 Better Insights**: Finite tag values enable proper aggregation and analysis
- **👥 Team Alignment**: Schema serves as documentation and contract

Stop the metric madness. Start with a schema.

---

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/kigster/datadog-statsd-schema](https://github.com/kigster/datadog-statsd-schema)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
