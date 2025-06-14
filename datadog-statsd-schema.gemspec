# rubocop:disable Gemspec/DevelopmentDependencies
# frozen_string_literal: true

require_relative "lib/datadog/statsd/schema/version"

Gem::Specification.new do |spec|
  spec.name = "datadog-statsd-schema"
  spec.version = Datadog::Statsd::Schema::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "An adapter or wrapper for Datadog Statsd that allows pre-declaring of metrics, tags and tag values and validating them against the schema."
  spec.description = "This gem is an adapter for the dogstatsd-ruby gem. Unlike the Datadog::Statsd metric sender, this gem supports pre-declaring schemas defining allowed metrics and their types, the tags that apply to them, and tag values that must be validated before streamed to Datadog. This approach allows for a more robust and consistent way to ensure that metrics follow a well-thought-out naming scheme and are validated before being sent to Datadog."
  spec.homepage = "https://github.com/kigster/datadog-statsd-schema"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kigster/datadog-statsd-schema"
  spec.metadata["changelog_uri"] = "https://github.com/kigster/datadog-statsd-schema"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "activesupport"
  spec.add_dependency "colored2"
  spec.add_dependency "dogstatsd-ruby"
  spec.add_dependency "dry-cli"
  spec.add_dependency "dry-schema"
  spec.add_dependency "dry-struct"
  spec.add_dependency "dry-types"
  spec.add_dependency "dry-validation"

  # Development dependencies
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec-its"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata["rubygems_mfa_required"] = "true"
end

# rubocop:enable Gemspec/DevelopmentDependencies
