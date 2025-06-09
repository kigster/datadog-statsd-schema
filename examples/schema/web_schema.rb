# frozen_string_literal: true

# vim: ft=ruby

namespace :web do
  tags do
    tag :environment, values: %w[production staging development]
    tag :service, values: %w[api web worker]
    tag :region, values: %w[us-east-1 us-west-2 eu-west-1]
  end

  namespace :requests do
    metrics do
      counter :total do
        description "Total HTTP requests"
        tags required: %i[environment service], allowed: %i[region]
      end

      distribution :duration do
        description "Request processing time in milliseconds"
        inherit_tags "web.requests.total"
      end
    end
  end

  metrics do
    gauge :memory_usage do
      description "Memory usage in bytes"
      tags required: %i[environment], allowed: %i[service]
    end
  end
end
