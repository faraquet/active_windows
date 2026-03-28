# frozen_string_literal: true

require "rails/railtie"

module ActiveWindows
  class Railtie < Rails::Railtie
    initializer "active_windows.active_record" do
      ActiveSupport.on_load :active_record do
        ActiveRecord::Relation.include(ActiveWindows::QueryMethods)
        ActiveRecord::Querying.delegate(:window, :row_number, to: :all)
      end
    end
  end
end
