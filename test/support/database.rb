# frozen_string_literal: true

require "active_record"

ActiveRecord::Base.establish_connection({ adapter: "sqlite3", database: ":memory:" })

require_relative "schema"

ActiveRecord::Relation.include(ActiveWindows::QueryMethods)
ActiveRecord::Querying.delegate(*ActiveWindows::QUERY_METHODS, to: :all)

Dir[File.join(File.dirname(__FILE__), "../models/*.rb")].each { |f| require f }
