# frozen_string_literal: true

require "active_record"

db_adapter = ENV.fetch("DB_ADAPTER", "sqlite3")

case db_adapter
when "postgresql"
  ActiveRecord::Base.establish_connection({
    adapter: "postgresql",
    database: ENV.fetch("POSTGRES_DB", "active_windows_test"),
    username: ENV.fetch("POSTGRES_USER", "postgres"),
    password: ENV.fetch("POSTGRES_PASSWORD", ""),
    host: ENV.fetch("POSTGRES_HOST", "localhost"),
    port: ENV.fetch("POSTGRES_PORT", "5432")
  })
when "mysql2"
  ActiveRecord::Base.establish_connection({
    adapter: "mysql2",
    database: ENV.fetch("MYSQL_DB", "active_windows_test"),
    username: ENV.fetch("MYSQL_USER", "root"),
    password: ENV.fetch("MYSQL_PASSWORD", ""),
    host: ENV.fetch("MYSQL_HOST", "127.0.0.1"),
    port: ENV.fetch("MYSQL_PORT", "3306")
  })
else
  ActiveRecord::Base.establish_connection({ adapter: "sqlite3", database: ":memory:" })
end

require_relative "schema"

ActiveRecord::Relation.include(ActiveWindows::QueryMethods)
ActiveRecord::Querying.delegate(*ActiveWindows::QUERY_METHODS, to: :all)

Dir[File.join(File.dirname(__FILE__), "../models/*.rb")].each { |f| require f }
