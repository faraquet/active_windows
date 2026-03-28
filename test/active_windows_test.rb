# frozen_string_literal: true

require "test_helper"

class ActiveWindowsTest < Minitest::Test
  def test_has_version_number
    refute_nil ActiveWindows::VERSION
  end
end
