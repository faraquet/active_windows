require "rails/railtie"
module ActiveWindows
  class Railtie < Rails::Railtie
    initializer "active_windows.active_record" do
      ActiveSupport.on_load :active_record do
        include ActiveWindows::ActiveRecordExtensions
      end
    end
  end
end
