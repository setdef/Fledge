# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "yaml"

# ruby-spec.yml takes the runtimes of the run that calls it, and trunk's
# newest passing run's only when it runs by itself, at night or by hand.
# A called workflow sees the caller's event, and ci.yml runs that cut.yml
# and pin-watch.yml dispatch are workflow_dispatch events: choosing by the
# event sent those runs' ruby/spec jobs to an older runtime, whose file
# name a release's version did not match.
class WorkflowRubySpecTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  WORKFLOW = YAML.load_file(File.join(ROOT, ".github/workflows/ruby-spec.yml"), aliases: true)

  def test_the_plan_tells_a_run_by_itself_by_the_workflow_name_which_a_caller_does_not_share
    assert_equal "ruby/spec", WORKFLOW.fetch("name")
    assert_equal "${{ github.workflow == 'ruby/spec' }}", plan_step.dig("env", "BY_ITSELF")
  end

  def test_the_plan_takes_trunks_runtimes_only_for_a_run_by_itself_never_by_the_event
    script = plan_step.fetch("run")

    assert_includes script, 'if [ "$BY_ITSELF" = true ]; then'
    refute_match(/GITHUB_EVENT_NAME/, script, "the event is the caller's, so it cannot say whether this workflow was called")
  end

  def test_ci_calls_it_by_a_name_of_its_own
    ci = YAML.load_file(File.join(ROOT, ".github/workflows/ci.yml"), aliases: true)

    refute_equal WORKFLOW.fetch("name"), ci.fetch("name")
    assert_equal "./.github/workflows/ruby-spec.yml", ci.dig("jobs", "ruby-spec", "uses")
  end

  private def plan_step = WORKFLOW.dig("jobs", "plan", "steps").find { |step| step["id"] == "plan" }
end
