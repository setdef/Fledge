# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# What the Android integration tests share
# (test/integration/mobile_extensions_build_test.rb,
# test/integration/mobile_extension_symbols_test.rb, and
# test/integration/mobile_default_gems_test.rb): on a computer without
# the Android runtime rake runtime[android] writes, the NDK, CMake, Rust's
# Android targets, or an Android device or emulator, the tests that need
# it skip, unless FLEDGE_REQUIRE_ANDROID is set, as CI's Mobile apps
# (Android emulator) job sets it, where a skip would pass a job that ran
# none of them.
module AndroidRequired
  def android_missing(message)
    ENV["FLEDGE_REQUIRE_ANDROID"] ? flunk(message) : skip(message)
  end
end
