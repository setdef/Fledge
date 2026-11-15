# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"

# An integration test may read a runtime a build left behind
# (FakeRuntime.real); test/test_task_test.rb checks that a unit test
# may not.
class TierTest < Minitest::Test
  def test_an_integration_test_may_read_a_runtime_a_build_left_behind
    assert FakeRuntime.real
  end
end
