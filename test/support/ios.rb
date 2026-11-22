# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# What the iOS integration tests share
# (test/integration/mobile_extensions_build_test.rb and
# test/integration/mobile_default_gems_test.rb): on a computer that is
# not a Mac, or without the iOS runtime rake runtime[ios] writes, CMake,
# or Rust's iOS targets, the tests that need it skip, unless
# FLEDGE_REQUIRE_IOS is set, as CI's iOS integration tests (iOS Simulator)
# job sets it, where a skip would pass a job that ran none of them.
module IOSRequired
  def ios_missing(message)
    ENV["FLEDGE_REQUIRE_IOS"] ? flunk(message) : skip(message)
  end
end
