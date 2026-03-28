# frozen_string_literal: true

require_relative "lib/active_windows/version"

Gem::Specification.new do |spec|
  spec.name = "active_windows"
  spec.version = ActiveWindows::VERSION
  spec.authors = ["Andrei Andriichuk"]
  spec.email = ["andreiandriichuk@gmail.com"]

  spec.summary = "A Ruby DSL for SQL window functions in ActiveRecord"
  spec.description = "Expressive, chainable DSL for SQL window functions (ROW_NUMBER, RANK, LAG, LEAD, SUM, etc.) " \
                     "that integrates naturally with ActiveRecord query methods."
  spec.homepage = "https://github.com/andreiandriichuk/active_windows"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/andreiandriichuk/active_windows"
  spec.metadata["changelog_uri"] = "https://github.com/andreiandriichuk/active_windows/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

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

  spec.add_dependency "activerecord", ">= 8.0"
  spec.add_dependency "activesupport", ">= 8.0"

  spec.add_development_dependency "bundler", ">= 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rails", ">= 8.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "sqlite3", ">= 2.1"
end
