# frozen_string_literal: true

require "active_record"

ActiveRecord::Base.establish_connection({ adapter: "sqlite3", database: ":memory:" })

# Load the schema
require_relative "schema"

# Integrate ActiveWindows into ActiveRecord
ActiveRecord::Relation.include(ActiveWindows::QueryMethods)
ActiveRecord::Querying.delegate(:window, :row_number, to: :all)

# Load test models
Dir[File.join(File.dirname(__FILE__), "../models/*.rb")].each { |f| require f }
