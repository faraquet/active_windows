# frozen_string_literal: true

require "bundler/setup"
require "rspec"
require "active_windows"
require_relative "support/database"

# This is crucial - it loads RSpec's DSL methods like 'describe', 'it', etc.
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    [User].each(&:delete_all)
  end
end
