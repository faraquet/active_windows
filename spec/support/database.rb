require 'active_record'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)


# Load the schema
require_relative 'schema'

# Load test models
Dir[File.join(File.dirname(__FILE__), '../models/*.rb')].each { |f| require f }
