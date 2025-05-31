#!/usr/bin/env ruby
# frozen_string_literal: true

# vim: ft=ruby

require_relative "shared"

# This schema defines a namespace for marathon metrics and tags.
marathon_schema = Datadog.schema do
  namespace "marathon" do
    namespace "started" do
      tags do
        tag :course, values: %w[sf-marathon new-york]
        tag :length, values: [26.212, 42.195]
        tag :units, values: %w[miles km]
      end
      metrics do
        counter "total", description: "Marathon started"
        distribution "duration", description: "Marathon duration"
      end
    end
  end
end

emitter = Datadog.emitter(
  "simple_emitter",
  schema: marathon_schema,
  validation_mode: :strict,
  tags: {
    course: "sf-marathon",
    length: 26.212,
    units: "miles"
  }
)

emitter.increment("marathon.started.total", by: 3, tags: { course: "new-york" })
emitter.increment("marathon.started.total", by: 8, tags: { course: "new-york" })

emitter.distribution("marathon.started.duration", 43.13, tags: { course: "new-york" })
emitter.distribution("marathon.started.duration", 41.01, tags: { course: "new-york" })

def send_invalid
  yield
rescue Datadog::Statsd::Schema::SchemaError
  # ignore
end

send_invalid do
  emitter.distribution("marathon.finished.duration", 21.23, tags: { course: "new-york" })
end

send_invalid do
  emitter.distribution("marathon.started.duration", 21.23, tags: { course: "austin" })
end
