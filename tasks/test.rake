# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "minitest/test_task"

# Clear the default test task created by Minitest::TestTask if it exists
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

# Rake::TestTask runs just the named files when TEST is set, as
# "rake test TEST=test/foo_test.rb" (rake 13.4.2, lib/rake/testtask.rb,
# lines 18-31 and 165-167: comma-separated names). Minitest::TestTask
# reads N, X, TESTOPTS and A but not TEST (minitest 6.0.6,
# lib/minitest/test_task.rb, lines 166-181), so without this "rake test
# TEST=..." silently ran the whole suite. Dir[] expands a glob too.
TEST_GLOBS = ENV.fetch("TEST", "test/**/*_test.rb").split(",")

# Every test runs with Ruby's warnings on, so a warning shows in the
# gate's output instead of in a user's terminal.
TEST_TASK = Minitest::TestTask.create(:test) do |t|
  t.test_globs = TEST_GLOBS
  t.warning = true
end
