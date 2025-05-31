# frozen_string_literal: true

RSpec.describe Datadog::Statsd::Schema do
  it 'has a version number' do
    expect(Datadog::Statsd::Schema::VERSION).not_to be_nil
  end
end
