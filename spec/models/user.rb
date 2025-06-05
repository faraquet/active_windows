class User < ActiveRecord::Base
  # The ActiveWindows extensions should be automatically included via the Railtie
  # But let's make sure it's working by explicitly including it if needed
  include ActiveWindows::ActiveRecordExtensions unless included_modules.include?(ActiveWindows::ActiveRecordExtensions)
end
