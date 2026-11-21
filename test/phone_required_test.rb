# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/android"
require_relative "support/ios"

# What a phone's integration test does for want of what it needs
# (test/support/android.rb and test/support/ios.rb): it skips, unless
# the phone's FLEDGE_REQUIRE_ variable is set, as CI's job for that phone
# sets it, and then it fails, so a job that ran none of the tests cannot
# pass.
class PhoneRequiredTest < Minitest::Test
  # A test of a phone, run by hand: what its missing call raises.
  class Phone < Minitest::Test
    include AndroidRequired
    include IOSRequired
  end

  VARIABLES = %w[FLEDGE_REQUIRE_ANDROID FLEDGE_REQUIRE_IOS].freeze

  # What the block raised with +variable+ set to +value+ and the other
  # phone's variable unset.
  def raised(variable, value)
    saved = VARIABLES.to_h { |name| [name, ENV.fetch(name, nil)] }
    VARIABLES.each { |name| ENV[name] = nil }
    ENV[variable] = value
    yield Phone.new("phone")
  rescue Minitest::Assertion => e
    e
  ensure
    saved.each { |name, was| ENV[name] = was }
  end

  def test_each_phone_skips_for_want_of_what_it_needs_unless_its_variable_asks
    { "FLEDGE_REQUIRE_ANDROID" => :android_missing, "FLEDGE_REQUIRE_IOS" => :ios_missing }.each do |variable, call|
      skipped = raised(variable, nil) { |test| test.public_send(call, "no runtime") }
      failed = raised(variable, "1") { |test| test.public_send(call, "no runtime") }

      assert_instance_of Minitest::Skip, skipped, call
      assert_equal "no runtime", skipped.message
      assert_instance_of Minitest::Assertion, failed, call
      assert_equal "no runtime", failed.message
    end
  end

  def test_one_phones_variable_leaves_the_other_phones_tests_skipping
    assert_instance_of Minitest::Skip, raised("FLEDGE_REQUIRE_ANDROID", "1") { |test| test.ios_missing("no runtime") }
    assert_instance_of Minitest::Skip, raised("FLEDGE_REQUIRE_IOS", "1") { |test| test.android_missing("no runtime") }
  end
end
