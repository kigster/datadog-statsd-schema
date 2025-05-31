# frozen_string_literal: true

require 'spec_helper'
require 'active_support/core_ext/module/delegation'
require 'active_support/core_ext/string/inflections'

module Datadog
  class Statsd
    module Schema
      RSpec.describe Emitter do
        let(:mock_statsd) { instance_double(::Datadog::Statsd) }

        before do
          allow(described_class).to receive(:statsd).and_return(mock_statsd)
        end

        describe '.configure' do
          it 'allows setting global tags' do
            described_class.configure do |config|
              config.env = 'test'
              config.version = '1.0.0'
            end

            expect(described_class.global_tags.env).to eq('test')
            expect(described_class.global_tags.version).to eq('1.0.0')
          end
        end

        describe '#initialize' do
          it 'initializes with a string described_class' do
            emitter = described_class.new('test')
            expect(emitter).to be_a(described_class)
            expect(emitter.tags[:emitter]).to eq('test')
          end

          it 'initializes with a class described_class' do
            emitter = described_class.new(String)
            expect(emitter.tags[:emitter]).to eq('string')
          end

          it 'processes module names correctly' do
            emitter = described_class.new(::Datadog::Statsd::Schema::Emitter)
            expect(emitter.tags[:emitter]).to eq('datadog.statsd.schema.emitter')
          end

          it 'raises error when all arguments are nil' do
            expect do
              described_class.new
            end.to raise_error(ArgumentError, /use class methods/)
          end
        end

        describe '#normalize_arguments' do
          context 'with metric in constructor' do
            let(:emitter) { described_class.new(nil, metric: 'test.metric') }

            it 'uses constructor metric when no args provided' do
              expect(mock_statsd).to receive(:increment).with('test.metric')
              emitter.increment
            end

            it 'uses constructor metric when first arg is nil' do
              expect(mock_statsd).to receive(:increment).with('test.metric')
              emitter.increment(nil)
            end

            it 'uses provided metric when first arg is not nil' do
              expect(mock_statsd).to receive(:increment).with('other.metric')
              emitter.increment('other.metric')
            end

            it 'preserves additional positional arguments' do
              expect(mock_statsd).to receive(:gauge).with('test.metric', 100)
              emitter.gauge(nil, 100)
            end

            it 'supports optional has arguments' do
              expect(mock_statsd).to receive(:increment).with('test.metric', by: 10)
              emitter.increment('test.metric', by: 10)
            end
          end

          context 'with tags in constructor' do
            let(:emitter) { described_class.new(nil, tags: { env: 'test', service: 'api' }) }

            it 'includes constructor tags' do
              expect(mock_statsd).to receive(:increment).with('test.metric', tags: { env: 'test', service: 'api' })
              emitter.increment('test.metric')
            end

            it 'merges constructor tags with method tags' do
              expect(mock_statsd).to receive(:increment).with(
                'test.metric',
                tags: { env: 'test', service: 'api', user_id: 123 }
              )
              emitter.increment('test.metric', tags: { user_id: 123 })
            end

            it 'method tags override constructor tags' do
              expect(mock_statsd).to receive(:increment).with(
                'test.metric',
                tags: { env: 'production', service: 'api' }
              )
              emitter.increment('test.metric', tags: { env: 'production' })
            end
          end

          context 'with ab_test in constructor' do
            let(:emitter) { described_class.new(nil, ab_test: { 'login_test_2025' => 'control' }) }

            it 'converts ab_test to tags' do
              expect(mock_statsd).to receive(:increment).with(
                'test.metric',
                tags: { ab_test_name: 'login_test_2025', ab_test_group: 'control' }
              )
              emitter.increment('test.metric')
            end

            it 'handles multiple ab_test entries (last one wins)' do
              emitter = described_class.new(nil, ab_test: {
                                              'login_test_2025'  => 'control',
                                              'signup_test_2025' => 'variant_a'
                                            })

              expect(mock_statsd).to receive(:increment).with(
                'test.metric',
                tags: { ab_test_name: 'signup_test_2025', ab_test_group: 'variant_a' }
              )
              emitter.increment('test.metric')
            end
          end

          context 'with ab_test in both constructor and method call' do
            let(:emitter) { described_class.new(nil, ab_test: { 'login_test_2025' => 'control' }) }

            it 'method ab_test overrides constructor ab_test' do
              expect(mock_statsd).to receive(:increment).with(
                'test.metric',
                tags: { ab_test_name: 'signup_test', ab_test_group: 'variant_a' }
              )
              emitter.increment('test.metric', ab_test: { 'signup_test' => 'variant_a' })
            end
          end

          context 'with sample_rate in constructor' do
            let(:emitter) { described_class.new(nil, sample_rate: 0.5) }

            it 'includes constructor sample_rate' do
              expect(mock_statsd).to receive(:increment).with('test.metric', sample_rate: 0.5)
              emitter.increment('test.metric')
            end

            it 'method sample_rate overrides constructor sample_rate' do
              expect(mock_statsd).to receive(:increment).with('test.metric', sample_rate: 0.1)
              emitter.increment('test.metric', sample_rate: 0.1)
            end

            it 'does not include sample_rate when it is 1.0 (default)' do
              emitter = described_class.new(nil, sample_rate: 1.0)
              expect(mock_statsd).to receive(:increment).with('test.metric')
              emitter.increment('test.metric')
            end
          end

          context 'with described_class in constructor' do
            let(:emitter) { described_class.new('TestController') }

            it 'includes described_class tag' do
              expect(mock_statsd).to receive(:increment).with(
                'test.metric',
                tags: { emitter: 'test_controller' }
              )
              emitter.increment('test.metric')
            end
          end

          context 'with complex combination' do
            let(:emitter) do
              described_class.new(
                'UserController',
                metric: 'users.action',
                tags: { env: 'test' },
                ab_test: { 'login_test' => 'control' },
                sample_rate: 0.8
              )
            end

            it 'combines all constructor options correctly' do
              expect(mock_statsd).to receive(:increment).with(
                'users.action',
                tags: {
                  emitter:       'user_controller',
                  env:           'test',
                  ab_test_name:  'login_test',
                  ab_test_group: 'control',
                  user_id:       456
                },
                sample_rate: 0.8
              )
              emitter.increment(tags: { user_id: 456 })
            end

            it 'allows method call to override everything' do
              expect(mock_statsd).to receive(:gauge).with(
                'custom.metric',
                100,
                tags: {
                  emitter:       'user_controller',
                  env:           'production',
                  ab_test_name:  'new_test',
                  ab_test_group: 'variant_b',
                  user_id:       789
                },
                sample_rate: 0.1
              )
              emitter.gauge(
                'custom.metric',
                100,
                tags: { env: 'production', user_id: 789 },
                ab_test: { 'new_test' => 'variant_b' },
                sample_rate: 0.1
              )
            end
          end
        end

        describe 'method forwarding' do
          let(:emitter) { described_class.new('Email::SenderController') }
          let(:expected_tags) { { emitter: 'email.sender_controller' } }

          it 'forwards increment calls' do
            expect(mock_statsd).to receive(:increment).with(
              'test.counter',
              by: 2,
              tags: expected_tags
            )

            emitter.increment('test.counter', by: 2)
          end

          it 'forwards gauge calls' do
            expect(mock_statsd).to receive(:gauge)
              .with('test.gauge', 100, tags: expected_tags)

            emitter.gauge('test.gauge', 100)
          end

          it 'forwards histogram calls' do
            expect(mock_statsd).to receive(:histogram)
              .with('test.histogram', 0.5, tags: expected_tags)
            emitter.histogram('test.histogram', 0.5)
          end

          it 'forwards distribution calls' do
            expect(mock_statsd).to receive(:distribution)
              .with('test.distribution', 0.3, tags: expected_tags)
            emitter.distribution('test.distribution', 0.3)
          end
        end
      end
    end
  end
end
