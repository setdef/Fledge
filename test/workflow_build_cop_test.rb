# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/build_cop"
require "yaml"

# build-cop.yml (doc/contributors/design/releases.md, "The build cop"):
# it follows CI by the name GitHub matches workflow_run by, on trunk and
# on the branches it bisects on, and on a schedule, since GitHub does
# not say whether a run its own token started ends with a workflow_run;
# a run by hand changes nothing unless asked; and its script starts the
# bisecting runs on the branches tasks/build_cop.rb reads them from.
class WorkflowBuildCopTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_it_follows_ci_on_trunk_and_the_bisect_branches_and_on_a_schedule
    on = workflow("build-cop.yml").fetch(true)
    trigger = on.fetch("workflow_run")

    assert_equal [workflow("ci.yml").fetch("name")], trigger.fetch("workflows")
    assert_equal ["trunk", "#{BuildCop::BISECT}**"], trigger.fetch("branches")
    assert_equal ["completed"], trigger.fetch("types")
    refute_empty on.fetch("schedule")
    assert on.dig("workflow_dispatch", "inputs", "dry-run", "default")
  end

  # ci.yml runs on a dispatch, which is how the cop starts a run of one
  # commit on its branch, and of the revert on trunk.
  def test_ci_runs_on_the_dispatch_the_cop_starts
    assert workflow("ci.yml").fetch(true).key?("workflow_dispatch")
  end

  def test_one_cop_at_a_time_and_none_cancelled
    assert_equal({ "group" => "build-cop", "cancel-in-progress" => false }, workflow("build-cop.yml").fetch("concurrency"))
  end

  def test_it_starts_runs_with_its_own_token_and_pushes_with_the_apps
    job = workflow("build-cop.yml").dig("jobs", "cop")
    mint = job.fetch("steps").find { |step| step["id"] == "push-token" }
    step = job.fetch("steps").last

    assert_equal({}, workflow("build-cop.yml").fetch("permissions"))
    assert_equal({ "contents" => "read", "actions" => "write" }, job.fetch("permissions"))
    assert_equal ".github/scripts/build-cop.sh", step.fetch("run")
    assert_equal "${{ steps.push-token.outputs.token }}", step.dig("env", "BUILD_COP_PUSH_TOKEN")
    assert_equal({ "permission-contents" => "write", "permission-workflows" => "write" }, mint.fetch("with").slice("permission-contents", "permission-workflows"))
    assert_equal false, job.fetch("steps").first.dig("with", "persist-credentials")
  end

  # The App's secrets belong to the environment release, which only runs
  # of trunk may use, as cut.yml's do.
  def test_it_names_the_environment_that_holds_the_apps_secrets
    assert_equal "release", workflow("build-cop.yml").dig("jobs", "cop", "environment")
    assert_equal "release", workflow("cut.yml").dig("jobs", "cut", "environment")
  end

  def test_its_script_bisects_on_the_branches_the_task_reads
    script = File.read(File.join(ROOT, ".github/scripts/build-cop.sh"))

    assert_includes script, "ruby tasks/build_cop.rb"
    assert_includes script, "branch=#{BuildCop::BISECT}$commit"
    assert_includes script, "'#{BuildCop::BISECT}*'"
    BuildCop::Step.of(:none, "").to_output.lines.map { |line| line[/\A\w+/] }.each do |field|
      assert_includes script, "$(field #{field})"
    end
  end

  private def workflow(name)
    YAML.load_file(File.join(ROOT, ".github", "workflows", name), aliases: true)
  end
end
