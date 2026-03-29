# frozen_string_literal: true

require "active_windows/version"
require "active_windows/active_record_extensions"
require "active_windows/railtie" if defined?(Rails::Railtie)

module ActiveWindows
  class Error < StandardError; end

  QUERY_METHODS = %i[window].freeze
end
