require 'active_record'
require 'logger'

# Configure ActiveRecord for testing
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

# Optional: Enable logging for debugging
# ActiveRecord::Base.logger = Logger.new(STDOUT)

# Load the schema
require_relative 'schema'

# Load test models
Dir[File.join(File.dirname(__FILE__), '../models/*.rb')].each { |f| require f }
