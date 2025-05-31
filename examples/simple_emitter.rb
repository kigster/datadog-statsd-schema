#!/usr/bin/env ruby
# frozen_string_literal: true

# vim: ft=ruby

require_relative "shared"

# This emitter has no schema and allows any combination of metrics and tags.
emitter = Datadog.emitter(
  "simple_emitter",
  metric: "marathon.started",
  tags: {
    course: "sf-marathon",
    length: 26.212,
    units: "miles"
  }
)

emitter.increment("total", by: 3, tags: { course: "new-york" })
emitter.increment("total", by: 8, tags: { course: "new-york" })

emitter.distribution("duration", 43.13, tags: { course: "new-york" })
emitter.distribution("duration", 41.01, tags: { course: "new-york" })
