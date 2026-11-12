# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "rake"
require_relative "../tasks/test_tiers"

# The test tasks (tasks/test.rake): rake test runs the unit tier, rake
# test:integration the integration tier, rake test:all both, and TEST
# names the files to run instead, as Rake::TestTask's does. Each test
# defines the tasks in a Rake application of its own and reads the
# command a task would run rather than running it, so a task that ran
# the wrong files fails here instead of starting the whole suite, this
# test among it, over and over.
class TestTaskTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # The test files the task +name+ would run, with TEST set to +test+.
  def files(name, test: nil)
    saved = ENV.fetch("TEST", nil)
    ENV["TEST"] = test
    out, = capture_io do
      Rake.with_application(Rake::Application.new) do
        load File.join(ROOT, "tasks", "test.rake")
        Rake::Task["#{name}:cmd"].invoke
      end
    end
    out.scan(/require "([^"]+_test\.rb)"/).flatten.sort
  ensure
    ENV["TEST"] = saved
  end

  def test_the_two_tiers_are_every_test_file_once
    unit = TestTiers.files(:unit, ROOT)
    integration = TestTiers.files(:integration, ROOT)

    assert_equal Dir.glob("test/**/*_test.rb", base: ROOT).sort, (unit + integration).sort
    assert_empty unit & integration
    assert_includes unit, "test/version_test.rb"
    assert_includes integration, "test/integration/built_app_test.rb"
    assert(integration.all? { |path| path.start_with?("test/integration/") })
  end

  # A new test file is a unit test unless it is in test/integration.
  def test_a_file_is_an_integration_test_only_in_test_integration
    Dir.mktmpdir do |root|
      %w[test/new_test.rb test/support/helper_test.rb test/integration/slow_test.rb test/integration/more/deep_test.rb test/fixtures/app.rb]
        .each { |path| FileUtils.mkdir_p(File.dirname(File.join(root, path))) && File.write(File.join(root, path), "") }

      assert_equal %w[test/new_test.rb test/support/helper_test.rb], TestTiers.files(:unit, root)
      assert_equal %w[test/integration/more/deep_test.rb test/integration/slow_test.rb], TestTiers.files(:integration, root)
      assert_equal TestTiers.files(:unit, root) + TestTiers.files(:integration, root), TestTiers.files(:all, root)
    end
  end

  def test_each_task_runs_its_tier
    assert_equal TestTiers.files(:unit, ROOT), files("test")
    assert_equal TestTiers.files(:integration, ROOT), files("test:integration")
    assert_equal TestTiers.files(:all, ROOT).sort, files("test:all")
  end

  def test_test_names_the_files_to_run_whatever_their_tier
    named = %w[test/cli_test.rb test/integration/exe_test.rb test/version_test.rb]

    assert_equal named, files("test", test: named.join(","))
    assert_equal named, files("test:all", test: named.join(","))
    assert_equal %w[test/version_test.rb], files("test:integration", test: "test/version_test.rb")
  end
end
