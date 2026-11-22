# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "shellwords"
require "yaml"

# ci.yml runs each Windows platform's tests in two shards. Together they
# must run every test once: shard 1 the tests one pattern matches
# (minitest's -i, through N), shard 2 every other (-x, through X), with
# the same pattern, so that neither can lose a test the other does not
# run; and each step after the tests in one shard only.
class WorkflowShardsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_the_windows_shards_select_with_one_pattern_as_complements
    run = tests_step.fetch("run")

    assert_includes run, '1) export N="$SHARD_1_TESTS" ;;'
    assert_includes run, '2) export X="$SHARD_1_TESTS" ;;'
    assert_equal 2, run.scan(/\b[NX]=/).size, "the shards choose their tests by N and X only once each"
    assert_match(/^\s*bundle exec rake test:all\s*$/, run, "the shards run test:all, every test file, with no TEST=")
  end

  def test_the_windows_shards_are_one_and_two_and_the_step_knows_which
    assert_equal [1, 2], job.dig("strategy", "matrix", "shard")
    env = tests_step.fetch("env")

    assert_equal "${{ matrix.shard }}", env.fetch("SHARD")
    refute(env.key?("N") || env.key?("X"), "N and X come from the shard's case, never both at once")
  end

  def test_git_bash_hands_the_pattern_to_ruby_unchanged
    assert_includes tests_step.dig("env", "MSYS2_ENV_CONV_EXCL").split(";"), "N"
    assert_includes tests_step.dig("env", "MSYS2_ENV_CONV_EXCL").split(";"), "X"
  end

  def test_the_pattern_is_a_regexp_that_leaves_tests_to_each_shard
    pattern = tests_step.dig("env", "SHARD_1_TESTS")

    assert_match %r{\A/.+/\z}, pattern, "minitest reads a filter as a regexp only between slashes"
    # Minitest::TestTask escapes N and X with Shellwords.escape; on Windows
    # no shell takes the backslashes out, so \^ or \| reach minitest and
    # shard 1 runs nothing.
    assert_equal pattern, Shellwords.escape(pattern), "a pattern escaping changes means another thing on Windows"
    regexp = Regexp.new(pattern[1..-2])
    names = File.read(File.join(ROOT, "test/integration/built_app_test.rb")).scan(/^\s*def (test_\w+)/).flatten
    chosen = names.count { |name| regexp.match?("BuiltAppTest##{name}") }

    assert_operator chosen, :>, 0, "shard 1 runs no test"
    assert_operator chosen, :<, names.size, "shard 1 runs all of built_app_test.rb"
  end

  def test_each_step_after_the_tests_runs_in_one_shard
    steps = job.fetch("steps")
    after = steps.drop(steps.index(tests_step) + 1)
    shards = after.map { |step| step["if"].to_s[/\Amatrix\.shard == ([12])\z/, 1] }

    refute_empty after
    assert_empty after.zip(shards).filter_map { |step, shard| step["name"] if shard.nil? }, "steps that run in both shards"
    assert_equal %w[1 2], shards.uniq.sort, "the steps after the tests are shared between the shards"
  end

  private def job
    @job ||= YAML.load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true).fetch("jobs").fetch("test-windows")
  end

  private def tests_step
    job.fetch("steps").find { |step| step["name"] == "Run the tests" }
  end
end
