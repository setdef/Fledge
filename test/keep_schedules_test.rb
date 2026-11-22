# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/loopback_server"
require_relative "../tasks/keep_schedules"

# How the scheduled workflows are kept from being disabled for a quiet
# repository: each is asked for its state from GitHub's API, as a loopback
# server serves GitHub's own answer for pin-watch.yml with each state the
# API gives, and enabled again unless a person disabled it.
class KeepSchedulesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ANSWER = JSON.parse(File.read(File.join(__dir__, "fixtures/keep_schedules/pin-watch.json")))
  WORKFLOWS = "/repos/setdef/Fledge/actions/workflows"

  def keep(states, dry_run: false)
    routes = states.to_h { |file, state| ["#{WORKFLOWS}/#{file}", [200, {}, JSON.generate(ANSWER.merge("state" => state))]] }
    states.each_key { |file| routes["#{WORKFLOWS}/#{file}/enable"] = [204, {}, ""] }
    server = LoopbackServer.new(routes)
    github = GitHubAPI.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0)
    lines = KeepSchedules.new(github, dry_run:).call(states.keys)
    [lines, server.calls]
  ensure
    server&.stop
  end

  def test_an_active_workflow_and_one_github_disabled_are_enabled_and_a_persons_choice_is_left
    lines, calls = keep({ "pin-watch.yml" => "active", "ruby-spec.yml" => "disabled_inactivity", "ruby-master.yml" => "disabled_manually" })

    assert_equal [
      "pin-watch.yml: active; enabled again",
      "::warning::ruby-spec.yml: GitHub had disabled it for inactivity; enabled again",
      "ruby-master.yml: disabled_manually, a person's choice; left as it is",
], lines
    assert_equal [
      "GET #{WORKFLOWS}/pin-watch.yml",
      "PUT #{WORKFLOWS}/pin-watch.yml/enable",
      "GET #{WORKFLOWS}/ruby-spec.yml",
      "PUT #{WORKFLOWS}/ruby-spec.yml/enable",
      "GET #{WORKFLOWS}/ruby-master.yml",
], calls
  end

  def test_a_dry_run_reads_each_state_and_enables_nothing
    lines, calls = keep({ "pin-watch.yml" => "active", "ruby-spec.yml" => "disabled_inactivity" }, dry_run: true)

    assert_equal [
      "pin-watch.yml: active; would be enabled again (dry run)",
      "::warning::ruby-spec.yml: GitHub had disabled it for inactivity; would be enabled again (dry run)",
], lines
    assert_equal ["GET #{WORKFLOWS}/pin-watch.yml", "GET #{WORKFLOWS}/ruby-spec.yml"], calls
  end

  def test_a_refused_enable_stops_with_what_github_answered
    server = LoopbackServer.new("#{WORKFLOWS}/pin-watch.yml" => [200, {}, File.read(File.join(__dir__, "fixtures/keep_schedules/pin-watch.json"))],
      "#{WORKFLOWS}/pin-watch.yml/enable" => [403, {}, "Resource not accessible by integration"])
    github = GitHubAPI.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0)
    error = assert_raises(GitHubAPI::Error) { KeepSchedules.new(github, dry_run: false).call(["pin-watch.yml"]) }

    assert_includes error.message, "403 for PUT"
  ensure
    server&.stop
  end

  def test_the_scheduled_workflows_are_those_whose_triggers_name_a_schedule
    scheduled = KeepSchedules.scheduled(ROOT)

    assert_includes scheduled, "pin-watch.yml"
    assert_includes scheduled, "ruby-master.yml"
    refute_includes scheduled, "ci.yml"
    Dir[File.join(ROOT, ".github/workflows/*.yml")].each do |path|
      assert_equal File.read(path).match?(/^  schedule:$/), scheduled.include?(File.basename(path)), File.basename(path)
    end
  end

  def test_its_workflow_runs_each_day_with_the_least_rights_and_a_dry_run_by_hand
    workflow = YAML.load_file(File.join(ROOT, ".github/workflows/keep-schedules.yml"))
    job = workflow.dig("jobs", "keep")
    step = job.fetch("steps").find { |candidate| candidate["run"].to_s.start_with?("ruby tasks/keep_schedules.rb") }

    assert_includes KeepSchedules.scheduled(ROOT), "keep-schedules.yml"
    assert_equal({ "contents" => "read", "actions" => "write" }, job["permissions"])
    assert_equal "ruby tasks/keep_schedules.rb ${{ inputs.dry-run && '--dry-run' || '' }}", step["run"]
    assert_equal "${{ github.token }}", step.dig("env", "GH_TOKEN")
    assert_equal true, workflow.dig(true, "workflow_dispatch", "inputs", "dry-run", "default")
  end
end
