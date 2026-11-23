# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "stringio"

# Ruby reads each file under tasks/ with warnings on, as rake test and
# the gate run it, and says nothing: an unused variable is a warning
# only when the file is read with them on, so a test of the file that
# loads it before warnings are looked at does not show it.
class RubyWarningsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def warnings_of(path)
    verbose = $VERBOSE
    stderr = $stderr
    $VERBOSE = true
    $stderr = StringIO.new
    RubyVM::InstructionSequence.compile_file(path)
    $stderr.string
  ensure
    $VERBOSE = verbose
    $stderr = stderr
  end

  def test_no_task_file_warns_when_read
    files = Dir.glob("tasks/**/*.rb", base: ROOT).sort
    refute_empty files
    found = files.to_h { |file| [file, warnings_of(File.join(ROOT, file))] }.reject { |_, warnings| warnings.empty? }

    assert_empty found
  end
end
