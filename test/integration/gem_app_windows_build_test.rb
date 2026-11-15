# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/gem_app_build"

# fledge build for a gem-shaped app (ADR 005) for Windows, on Windows,
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
end
