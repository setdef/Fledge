# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/loopback_server"
require_relative "../tasks/build_cop"
require "json"
require "uri"

# How the build cop finds the commit that turned trunk's full run red
# (doc/contributors/design/releases.md, "The build cop"): it bisects the
# batch between the last green run and the first red one with runs of
# single commits, judges each by the jobs that failed in the red run,
# runs the first bad commit's failed jobs again, and names it to revert
# only when they fail twice. Each case is a trunk of six commits, A the
# oldest and F the newest, whose runs a loopback server serves at
# GitHub's paths, in the shape GitHub's API gives them.
class BuildCopTest < Minitest::Test
  COMMITS = ("a".."f").map { |name| name * 40 }.freeze

  NOW = Time.utc(2026, 11, 23, 12)

  # The job that failed in F's run.
  FAILED = "Test (x64-mingw-ucrt, 1 of 2)"

  def test_nothing_to_do_when_the_newest_finished_run_on_trunk_is_green
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "success"))

    assert_equal :none, step.action
    assert_includes step.reason, "is red"
  end

  def test_bisects_a_red_batch_after_a_green_run_at_its_middle
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure"))

    assert_equal :bisect, step.action
    assert_equal commit("c"), step.commit
    assert_includes step.reason, FAILED
    assert_includes step.reason, "4 commits between"
  end

  # Runs a newer push replaced while they waited ran no job, and tell
  # nothing.
  def test_a_cancelled_run_tells_nothing
    step = cop(ci_run("a", 1, "success"), ci_run("c", 3, "cancelled", jobs: []), ci_run("f", 2, "failure"))

    assert_equal :bisect, step.action
    assert_equal commit("c"), step.commit
  end

  def test_waits_while_a_bisecting_run_has_not_finished
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure"), ci_run("c", 3, nil, branch: "bisect/c"))

    assert_equal :wait, step.action
    assert_includes step.reason, commit("c")
  end

  # C passed the job that failed, and E failed it, so D is next; other
  # jobs of C's run that failed say nothing about this failure.
  def test_narrows_by_the_jobs_that_failed_in_the_red_run_alone
    step = cop(
      ci_run("a", 1, "success"), ci_run("f", 2, "failure"),
      ci_run("c", 3, "failure", branch: "bisect/c", jobs: [job(FAILED, "success"), job("Delivery (x64-mingw-ucrt)", "failure")]),
      ci_run("e", 4, "failure", branch: "bisect/e")
    )

    assert_equal :bisect, step.action
    assert_equal commit("d"), step.commit
  end

  def test_runs_the_first_bad_commits_failed_jobs_again_before_it_blames_it
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure"), ci_run("c", 3, "success", branch: "bisect/c"), ci_run("d", 4, "failure", branch: "bisect/d"))

    assert_equal :rerun, step.action
    assert_equal [commit("d"), 4], [step.commit, step.run]
  end

  def test_names_the_commit_to_revert_when_its_job_fails_again
    second = ci_run("d", 4, "failure", branch: "bisect/d", attempt: 2, jobs: [job(FAILED, "failure", attempt: 2)])
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure"), ci_run("c", 3, "success", branch: "bisect/c"), second)

    assert_equal :revert, step.action
    assert_equal [commit("d"), 4], [step.commit, step.run]
    assert_includes step.reason, "parent passed"
  end

  # A second attempt in which only another job failed again is no
  # second failure of the job that turned trunk red.
  def test_a_second_attempt_of_another_job_blames_nobody
    second = ci_run("d", 4, "failure", branch: "bisect/d", attempt: 2, jobs: [job(FAILED, "failure"), job("Gate", "failure", attempt: 2)])
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure"), ci_run("c", 3, "success", branch: "bisect/c"), second)

    assert_equal :rerun, step.action
  end

  # D's job passed when it was run again: a flake, so D is good and the
  # blame moves on to E.
  def test_a_job_that_passes_when_run_again_clears_its_commit
    healed = ci_run("d", 4, "success", branch: "bisect/d", attempt: 2, jobs: [job(FAILED, "success", attempt: 2)])
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure"), ci_run("c", 3, "success", branch: "bisect/c"), healed, ci_run("e", 5, "failure", branch: "bisect/e"))

    assert_equal :rerun, step.action
    assert_equal commit("e"), step.commit
  end

  # F's own run passing when run again makes F the newest green run.
  def test_a_red_run_that_passes_when_run_again_leaves_nothing_to_do
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "success", attempt: 2, jobs: [job(FAILED, "success", attempt: 2)]))

    assert_equal :none, step.action
  end

  def test_does_nothing_while_the_red_run_runs_again
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, nil, attempt: 2))

    assert_equal :none, step.action
  end

  # A batch of one commit after the green one blames it at once, once
  # its run has failed twice.
  def test_a_red_run_right_after_a_green_one_needs_no_bisecting
    step = cop(ci_run("e", 1, "success"), ci_run("f", 2, "failure"))

    assert_equal :rerun, step.action
    assert_equal [commit("f"), 2], [step.commit, step.run]
  end

  # A middle commit whose run finished without running the failed job,
  # as when no runner took it or an earlier job it needs failed, has its
  # failed jobs run again once, and is then left for a person.
  def test_a_middle_commits_run_that_did_not_run_the_job_runs_again_once
    untold = ci_run("c", 3, "failure", branch: "bisect/c", jobs: [job(FAILED, "skipped")])
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure"), untold)

    assert_equal [:rerun, 3], [step.action, step.run]

    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure"), untold.merge("run_attempt" => 2))

    assert_equal :stuck, step.action
    assert_includes step.reason, "run 3"
  end

  # A run that is red only for jobs cancelled, such as one no runner
  # took, is runnerless.yml's.
  def test_nothing_to_do_for_a_run_red_only_for_cancelled_jobs
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure", jobs: [job(FAILED, "cancelled")]))

    assert_equal :none, step.action
    assert_includes step.reason, "no job that failed"
  end

  def test_nothing_to_do_without_a_green_run_on_trunk
    step = cop(ci_run("f", 2, "failure"), ci_run("a", 1, "success", branch: "bisect/a"))

    assert_equal :none, step.action
  end

  # Pull requests' runs check out a merge, not the commit, and count for
  # nothing.
  def test_a_pull_requests_run_counts_for_nothing
    step = cop(ci_run("a", 1, "success"), ci_run("f", 2, "failure"), ci_run("c", 3, "success", event: "pull_request"))

    assert_equal commit("c"), step.commit
  end

  def test_its_output_is_lines_for_github_output
    step = BuildCop::Step.of(:revert, "why", commit: "abc", run: 4)

    assert_equal "action=revert\ncommit=abc\nrun=4\nreason=why\n", step.to_output
  end

  private def commit(name) = name * 40

  # A run of +name+'s commit: +conclusion+ nil for one still running.
  private def ci_run(name, id, conclusion, branch: "trunk", attempt: 1, event: "push", jobs: nil)
    jobs ||= [job(FAILED, (conclusion == "failure") ? "failure" : "success", attempt:)]
    {
      "id" => id,
      "head_sha" => commit(name),
      "head_branch" => branch,
      "event" => event,
      "run_attempt" => attempt,
      "status" => conclusion ? "completed" : "in_progress",
      "conclusion" => conclusion,
      "jobs" => jobs,
    }
  end

  private def job(name, conclusion, attempt: 1)
    { "name" => name, "status" => "completed", "conclusion" => conclusion, "run_attempt" => attempt }
  end

  # The cop's Step for COMMITS, newest first, with +runs+ served.
  private def cop(*runs)
    query = URI.encode_www_form(created: ">=2026-11-20", exclude_pull_requests: true, per_page: GitHubAPI::PER_PAGE, page: 1)
    listed = runs.map { |each| each.except("jobs") }
    routes = { "/repos/setdef/Fledge/actions/workflows/ci.yml/runs?#{query}" => [200, {}, JSON.generate(total_count: listed.size, workflow_runs: listed)] }
    runs.each do |each|
      path = "/repos/setdef/Fledge/actions/runs/#{each.fetch('id')}/jobs?filter=latest&per_page=#{GitHubAPI::PER_PAGE}&page=1"
      routes[path] = [200, {}, JSON.generate(total_count: each.fetch("jobs").size, jobs: each.fetch("jobs"))]
    end
    server = LoopbackServer.new(routes)
    BuildCop.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0, now: NOW).call(COMMITS.reverse)
  ensure
    server&.stop
  end
end
