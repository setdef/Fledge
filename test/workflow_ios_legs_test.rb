# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# ci.yml runs the iOS integration tests in legs, so that no step runs
# near its limit. Together the legs must run every test file
# that needs the iOS runtime, each once: a file that gets no leg would
# never run in CI, and one in two would run twice.
class WorkflowIOSLegsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_the_legs_run_each_file_that_needs_the_ios_runtime_once
    needing = Dir.glob("test/integration/*_test.rb", base: ROOT).select { |file| File.read(File.join(ROOT, file)).include?("IOSRequired") }
    given = legs.flat_map { |leg| leg.fetch("tests").split(",") }

    refute_empty needing
    assert_equal needing.sort, given.sort, "the iOS legs of ci.yml run each test file that includes IOSRequired once"
  end

  def test_each_leg_has_a_name_and_the_step_runs_its_files_under_the_step_limit
    names = legs.map { |leg| leg.fetch("leg") }

    assert_equal names.uniq, names
    assert_equal "${{ matrix.tests }}", step.dig("env", "TESTS")
    assert_operator step.fetch("timeout-minutes"), :<=, 25
  end

  private def legs
    job.dig("strategy", "matrix", "include")
  end

  private def step
    job.fetch("steps").find { |candidate| candidate["name"] == "Run the iOS integration tests" }
  end

  private def job
    @job ||= YAML.load_file(File.join(ROOT, ".github", "workflows", "ci.yml"), aliases: true).fetch("jobs").fetch("mobile-tests-ios")
  end
end
