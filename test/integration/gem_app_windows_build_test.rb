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

    assert_equal [0, "dist/my_app-x64-mingw-ucrt.zip\n"], [status, out], err
    assert_the_locked_gems_ship("dist/my_app-x64-mingw-ucrt", "ruby/lib/ruby/gems/4.1.0+5", windows)
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
    folder = File.join(@dir, "dist/my_app-x64-mingw-ucrt")

    File.write(File.join(root, "fledge.yml"), "windows:\n  visual_c_runtime: central\n")
    out, err, status = build(File.join(root, "exe/my_app"), host: "x64-mingw-ucrt")
    assert_equal [0, "dist/my_app-x64-mingw-ucrt.zip\n"], [status, out], err
    assert_includes File.read(File.join(folder, "fledge.cfg")), "\nvisual_c_runtime = msvcp140.dll vcruntime140.dll vcruntime140_1.dll\n"
    assert_empty Dir.glob("ruby/bin/ruby_builtin_dlls/{msvcp,vcruntime}*", base: folder)
  end

  # A gem's extension that imports a DLL of the runtime's by name, as
  # ffi's ffi_c.so compiled against MSYS2 imports libffi-8.dll, is refused
  # when the runtime holds that DLL only beside fiddle.so, where Windows
  # does not look for it, as Fledge 0.17.0's runtime held libffi-8.dll,
  # and builds when the runtime holds it in ruby_builtin_dlls.
  def test_a_runtime_dll_where_windows_does_not_look_is_refused_in_plain_words
    skip "a Windows app is built on Windows, with the real runtime's launchers and rcedit" unless FakeRuntime.windows
    windows = Fledge::Platform.find("x64-mingw-ucrt")
    linked = FakeGem.build(@gems, "linked", "1.0.0", platform: "x64-mingw-ucrt",
      files: { "lib/linked.so" => Binaries.pe(needed: %w[libgmp-10.dll KERNEL32.dll]) })
    root = project(dependencies: { "linked" => ">= 0" }, locked: [linked])
    built = lambda do |place|
      FakeRuntime.write(@runtimes, windows, extra: [Fledge::Entry.file(place, "MZ")])
      FileUtils.rm_rf(File.join(@dir, "dist"))
      build(File.join(root, "exe/my_app"), host: "x64-mingw-ucrt")
    end

    beside_fiddle = built.call("ruby/lib/ruby/gems/4.1.0+5/extensions/x64-mingw-ucrt/4.1.0+5/fiddle-1.1.8/libgmp-10.dll")
    assert_equal ["", 1], [beside_fiddle[0], beside_fiddle[2]], beside_fiddle[1]
    assert_includes beside_fiddle[1], "linked 1.0.0 (x64-mingw-ucrt)'s lib/linked.so needs libgmp-10.dll, which neither windows, nor Fledge's runtime, " \
      "nor the gem itself provides, so the app could not load it on another computer."
    assert_equal ["dist/my_app-x64-mingw-ucrt.zip\n", 0], built.call("ruby/bin/ruby_builtin_dlls/libgmp-10.dll").values_at(0, 2)
  end
end
