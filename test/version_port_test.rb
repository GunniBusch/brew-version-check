# frozen_string_literal: true

require "minitest/autorun"
require_relative "../app"

class VersionPortTest < Minitest::Test
  def test_detects_versions_from_known_urls
    assert_equal "1.2.3", Version.detect("https://github.com/org/project/archive/v1.2.3.tar.gz").to_s
    assert_equal "2023-09-28", Version.detect("https://example.com/project-2023-09-28.tar.gz").to_s
    assert_equal "5.0.0-alpha10", Version.detect("https://example.com/premake-5.0.0-alpha10-src.zip").to_s
  end

  def test_compare_orders_prerelease_tokens
    assert_operator Version.new("1.0.0-alpha1"), :<, Version.new("1.0.0-beta1")
    assert_operator Version.new("1.0.0-beta1"), :<, Version.new("1.0.0-rc1")
    assert_operator Version.new("1.0.0-rc1"), :<, Version.new("1.0.0")
  end

  def test_bridge_helpers
    assert_equal "2.4.1", BrewVersionBridge.detect_version("https://example.com/tool-2.4.1.tar.gz")
    assert_equal 0, BrewVersionBridge.compare_versions("1.2.3", "1.2.3")
    assert_equal(-1, BrewVersionBridge.compare_versions("1.2.3", "1.2.4"))
  end
end
