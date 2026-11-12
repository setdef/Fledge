# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/build_from"
require "open3"

# fledge build --from APP (ADR 032), through real streams, with the tools
# of the platform the app is for: on a Mac, plutil and codesign, which
# write and seal the new bundle; on Windows, the real Windows runtime's
# launchers and rcedit. test/build_from_test.rb covers the rest with
# fake runtimes alone.
class BuildFromToolsTest < Minitest::Test
  include BuildFromHelpers

  # On macOS a windowed app is its bundle, which --from takes as APP too,
  # and the new bundle is written and sealed again with the system's own
  # plutil and codesign.
  def test_on_macos_the_new_bundle_has_its_own_info_plist_and_seal
    skip "codesign and plutil are macOS's" unless RUBY_PLATFORM.include?("darwin")
    FakeRuntime.write(@runtimes, Fledge::Platform.find("arm64-darwin"), launcher: File.binread("/usr/bin/true"))
    from = built_player("kind: windowed\nidentifier: com.example.Player\ninstallers: []\n", host: "arm64-darwin-25")
    game("kind: windowed\nidentifier: com.example.Game\ninstallers: []\n")

    _, err, status = build("--from", File.join(from, "Player.app"), "game", host: "arm64-darwin-25")

    assert_equal [0, ""], [status, err]
    bundle = File.join(@dir, "dist", "Game-arm64-darwin", "Game.app")
    assert_equal ["Game.app"], Dir.children(File.dirname(bundle))
    plist, = Open3.capture2("plutil", "-extract", "CFBundleIdentifier", "raw", "-o", "-", File.join(bundle, "Contents", "Info.plist"))
    assert_equal "com.example.Game\n", plist
    _, verify, = Open3.capture3("codesign", "--verify", "--deep", "--strict", "--verbose=2", bundle)
    assert_includes verify, "valid on disk"
    assert_path_exists File.join(bundle, "Contents", "Resources", "app", "vendor", "greeter", "lib", "greeter.rb")
  end

  # A console app built from a windowed one on macOS takes the bundle's
  # program, signed again ad hoc so that it carries no seal of the old
  # app's.
  def test_on_macos_a_console_app_from_a_bundle_carries_none_of_its_signature
    skip "codesign is macOS's" unless RUBY_PLATFORM.include?("darwin")
    FakeRuntime.write(@runtimes, Fledge::Platform.find("arm64-darwin"), launcher: File.binread("/usr/bin/true"))
    from = built_player("kind: windowed\nidentifier: com.example.Player\ninstallers: []\n", host: "arm64-darwin-25")
    game
    FileUtils.rm_f(File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::Platform.find("arm64-darwin"))))

    _, err, status = build("--from", from, "game", host: "arm64-darwin-25")

    assert_equal [0, ""], [status, err]
    _, info, = Open3.capture3("codesign", "--display", "--verbose=2", File.join(@dir, "dist", "Game-arm64-darwin", "Game"))
    refute_includes info, "com.example.Player"
  end

  # On Windows the app carries the runtime's launchers, rcedit, and NSIS,
  # but not llvm-readobj, which reads compiled gems, and --from builds
  # none; with them, a Windows app is built from it with no runtime.
  def test_on_windows_an_app_with_build_tools_is_built_from_with_no_runtime
    skip "a Windows app is built on Windows, with the real runtime's launchers and rcedit" unless Gem.win_platform? && FakeRuntime.windows
    host = Fledge::Platform.local.name
    from = built_player("build_tools: true\n", host:)
    assert_equal %w[launcher.exe launcherw.exe rcedit.exe], Dir.children(File.join(from, "tools")).sort
    game("kind: windowed\nidentifier: com.example.Game\ninstallers: []\n")

    _, err, status = build("--from", from, "game", host:, env: no_runtime)

    assert_equal [0, ""], [status, err]
    folder = File.join(@dir, "dist", "Game-#{host}")
    assert_path_exists File.join(folder, "Game.exe")
    refute_path_exists File.join(folder, "tools")
  end
end
