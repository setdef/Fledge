# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class PlatformTest < Minitest::Test
  def test_names_are_the_rubygems_platforms_fledge_has_runtimes_for
    assert_equal %w[arm64-darwin x86_64-linux aarch64-linux], Fledge::Platform.names
    assert_predicate Fledge::Platform.names, :frozen?
  end

  def test_find_returns_a_known_platform
    Fledge::Platform.names.each do |name|
      platform = Fledge::Platform.find(name)

      assert_equal name, platform.name
      assert_equal name, platform.to_s
    end
  end

  def test_find_refuses_an_unknown_platform_and_lists_the_known_ones
    error = assert_raises(Fledge::Error) { Fledge::Platform.find("x64-mingw-ucrt") }

    assert_equal "'x64-mingw-ucrt' is not a target Fledge builds for. " \
      "Targets: arm64-darwin, x86_64-linux, aarch64-linux.", error.message
  end

  def test_local_drops_the_darwin_version
    assert_equal "arm64-darwin", Fledge::Platform.local(Gem::Platform.new("arm64-darwin-25")).name
    assert_equal "arm64-darwin", Fledge::Platform.local(Gem::Platform.new("arm64-darwin-23")).name
  end

  def test_local_maps_glibc_linux
    assert_equal "x86_64-linux", Fledge::Platform.local(Gem::Platform.new("x86_64-linux")).name
    assert_equal "aarch64-linux", Fledge::Platform.local(Gem::Platform.new("aarch64-linux")).name
    assert_equal "x86_64-linux", Fledge::Platform.local(Gem::Platform.new("x86_64-linux-gnu")).name
  end

  def test_local_refuses_platforms_without_runtimes
    %w[x86_64-darwin-23 x86_64-linux-musl x64-mingw-ucrt].each do |name|
      error = assert_raises(Fledge::Error) { Fledge::Platform.local(Gem::Platform.new(name)) }

      assert_includes error.message, "Fledge has no runtime for this computer's platform (#{Gem::Platform.new(name)})"
      assert_includes error.message, "--target: arm64-darwin, x86_64-linux, aarch64-linux"
    end
  end

  def test_local_defaults_to_this_computer
    expected = Fledge::Platform.local(Gem::Platform.local)
    assert_equal expected, Fledge::Platform.local
  rescue Fledge::Error
    assert_raises(Fledge::Error) { Fledge::Platform.local }
  end

  def test_unix_platforms_ship_tar_gz_and_unadorned_executables
    Fledge::Platform.names.each do |name|
      platform = Fledge::Platform.find(name)

      assert_equal ".tar.gz", platform.archive_extension
      assert_equal "hello", platform.executable("hello")
    end
  end
end
