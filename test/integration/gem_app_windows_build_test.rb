# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/binaries"
require_relative "../support/gem_app_build"

# fledge build for a gem-shaped app for Windows, on Windows,
# where the build edits the launchers with rcedit, so the fake runtime
# carries the real Windows runtime's (FakeRuntime.windows).
class GemAppWindowsBuildTest < Minitest::Test
  include GemAppBuild

  def test_the_locked_gems_ship_for_windows_beside_the_runtimes_own
    skip "a Windows app is built on Windows, with the real runtime's launchers and rcedit" unless FakeRuntime.windows
    root, _, windows = locked_gems_project

    out, err, status = build(File.join(root, "exe/my_app"), host: "x64-mingw-ucrt")

    assert_equal [0, "dist/MyApp-x64-mingw-ucrt.zip\n"], [status, out], err
    assert_the_locked_gems_ship("dist/MyApp-x64-mingw-ucrt", "ruby/lib/ruby/gems/4.1.0+5", windows)
  end

  # With windows: { visual_c_runtime: central } the app carries none of
  # Microsoft's Visual C++ runtime, and its fledge.cfg names each DLL of
  # it the gems need, which the launcher looks for in System32 before
  # Ruby starts.
  def test_the_launcher_is_told_the_visual_c_runtime_a_central_app_assumes
    skip "a Windows app is built on Windows, with the real runtime's launchers and rcedit" unless FakeRuntime.windows
    linked = FakeGem.build(@gems, "linked", "1.0.0", platform: "x64-mingw-ucrt",
      files: { "vendor/libui.x64.dll" => Binaries.pe(needed: %w[d2d1.dll DWrite.dll msvcrt.dll WINDOWSCODECS.dll MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll]) })
    root = project(dependencies: { "linked" => ">= 0" }, locked: [linked])
    folder = File.join(@dir, "dist/MyApp-x64-mingw-ucrt")

    File.write(File.join(root, "fledge.yml"), "windows:\n  visual_c_runtime: central\n")
    out, err, status = build(File.join(root, "exe/my_app"), host: "x64-mingw-ucrt")
    assert_equal [0, "dist/MyApp-x64-mingw-ucrt.zip\n"], [status, out], err
    assert_includes File.read(File.join(folder, "fledge.cfg")), "\nvisual_c_runtime = msvcp140.dll vcruntime140.dll vcruntime140_1.dll\n"
    assert_empty Dir.glob("ruby/bin/ruby_builtin_dlls/{msvcp,vcruntime}*", base: folder)
  end
end
