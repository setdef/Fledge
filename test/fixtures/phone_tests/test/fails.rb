# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# A suite with a failure, which fledge test must report, and exit 1 for,
# as ruby test/fails.rb does.
require "minitest/autorun"

class FailsTest < Minitest::Test
  def test_passes
    assert_equal 2, 1 + 1
  end

  def test_fails_on_purpose
    assert_equal 3, 1 + 1, "PhoneTests fails on purpose"
  end
end
