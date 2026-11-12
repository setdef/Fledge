# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"
require "rbconfig"

# "rake test TEST=test/foo_test.rb" runs just that file, as
# Rake::TestTask's does; Minitest::TestTask ignores TEST on its own. The
# test reads the command the task would run rather than running it, so a
# task that ignored TEST again fails here instead of starting the whole
# suite, this test among it, over and over.
class TestTaskTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def command(env)
    script = 'require "rake"; load "tasks/test.rake"; puts TEST_TASK.make_test_cmd'
    out, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, chdir: ROOT)
    assert_predicate status, :success?, out
    out
  end

  def test_test_names_the_files_to_run
    out = command("TEST" => "test/version_test.rb,test/cli_test.rb")

    assert_includes out, "test/version_test.rb"
    assert_includes out, "test/cli_test.rb"
    refute_includes out, "test/app_test.rb"
  end

  def test_without_test_every_test_file_runs
    out = command("TEST" => nil)

    assert_includes out, "test/version_test.rb"
    assert_includes out, "test/app_test.rb"
  end
end
