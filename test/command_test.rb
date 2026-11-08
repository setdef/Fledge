# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Fledge::Command runs the system's tools, which write in their
# console's encoding, such as a Windows OEM code page, not UTF-8.
class CommandTest < Minitest::Test
  def fails(stream) = "#{stream}.write(\"tar: \\xFC\".b); #{stream}.flush; exit 1"

  def test_a_failure_written_in_another_encoding_is_quoted_not_raised
    [
      -> { Fledge::Command.run(RbConfig.ruby, "-e", fails("$stdout"), install: "x") },
      -> { Fledge::Command.read(RbConfig.ruby, "-e", fails("$stderr"), install: "x") },
    ].each do |command|
      error = assert_raises(Fledge::Error) { command.call }
      assert_match(/failed \(.*\):\ntar: \uFFFD\z/, error.message)
      assert_predicate error.message, :valid_encoding?
    end
  end
end
