#!/usr/bin/env ruby
# frozen_string_literal: true

# vim: ft=ruby

require "bundler/setup"
require "datadog/statsd/schema"

require "git"
require "etc"
require "datadog/statsd"
require "amazing_print"

STATSD = Datadog::Statsd.new(
  "localhost", 8125
)

class FakeStatsd
  def initialize(...); end

  def method_missing(m, *args, **opts)
    puts "$statsd.#{m}(\n  '#{args.first}',#{args.drop(1).join(", ")}#{args.size > 1 ? "," : ""}\n  #{opts.inspect} -> { #{if block_given?
                                                                                                                             yield
                                                                                                                           end} } "
  end

  def respond_to_missing?(m, *)
    STATSD.respond_to?(m)
  end
end

FAKE_STATSD = FakeStatsd.new

Datadog::Statsd::Schema.configure do |config|
  # This configures the global tags that will be attached to all methods
  config.tags = {
    env: "development",
    arch: Etc.uname[:machine],
    version: Git.open(".").object("HEAD").sha
  }

  config.statsd = FAKE_STATSD
end
