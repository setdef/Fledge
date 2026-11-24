# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "visual_c_runtime_test"

# What a test that TestReaders.need skips leaves of its own teardown: on a
# computer with no tool that reads a format, a skip is all it reports.
class TestReadersTest < Minitest::Test
  def test_a_test_skipped_for_want_of_a_reader_has_no_teardown_error
    cache = TestReaders.instance_variable_get(:@all) || (TestReaders.all && TestReaders.instance_variable_get(:@all))
    kept = cache.dup
    required = ENV.delete("FLEDGE_REQUIRE_READERS")
    cache[FakeRuntime.real] = Fledge::Binary::Readers.new(commands: {}, install: "none")
    result = VisualCRuntimeTest.new("test_carries_nothing_when_nothing_needs_it").run

    assert_equal [Minitest::Skip], result.failures.map(&:class)
  ensure
    cache&.replace(kept)
    ENV["FLEDGE_REQUIRE_READERS"] = required if required
  end
end
