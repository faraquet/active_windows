# frozen_string_literal: true

require "active_windows/version"
require "active_windows/active_record_extensions"
require "active_windows/railtie" if defined?(Rails::Railtie)

module ActiveWindows
  class Error < StandardError; end

  QUERY_METHODS = %i[
    window row_number rank dense_rank percent_rank cume_dist ntile
    lag lead first_value last_value nth_value
    window_sum window_avg window_count window_min window_max
  ].freeze
end
