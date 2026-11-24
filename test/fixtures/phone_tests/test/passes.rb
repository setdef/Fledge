# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# A suite that passes, and warns on standard error, which fledge test
# prints to its own.
require "minitest/autorun"

class PassesTest < Minitest::Test
  def test_passes
    warn "PhoneTests warns on standard error"
    assert_equal 2, 1 + 1
  end
end
