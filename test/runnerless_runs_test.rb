# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/loopback_server"
require_relative "../tasks/runnerless_runs"
require "json"
require "yaml"

# How a run on trunk that is red only because GitHub never gave one of
# its jobs a runner comes right on its own, and how every other red run
# stays as red as it is (doc/contributors/design/releases.md, "A job no
# runner took"). Each case is GitHub's own answer for a real run of this
# repository, recorded in test/fixtures/runnerless with only the fields
# read here kept, and served by a loopback server at GitHub's paths.
class RunnerlessRunsTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/runnerless", __dir__)

  # Run 44536045262, attempt 1: Runtime (arm64-darwin) waited 24 minutes
  # for a macOS runner and was cancelled with no steps; the jobs that
  # need it were skipped.
  def test_runs_again_a_run_whose_only_red_job_never_got_a_runner
    with_case("44536045262-1") do |server, runs|
      assert_equal :rerun, runs.call(44_536_045_262, 1).action
      assert_equal ["POST /repos/setdef/Fledge/actions/runs/44536045262/rerun-failed-jobs"], posts(server)
    end
  end

  # Run 44513751573, attempt 1, a release commit's run: Delivery
  # (arm64-darwin) never got a runner.
  def test_runs_again_a_release_commits_run_whose_delivery_never_got_a_runner
    with_case("44513751573-1") do |server, runs|
      verdict = runs.call(44_513_751_573, 1)
      assert_equal :rerun, verdict.action
      assert_includes verdict.reason, "Delivery (arm64-darwin)"
      assert_equal 1, posts(server).size
    end
  end

  # Run 44093239386, the ruby/spec nightly of 2026-11-17: its iOS job
  # never got a runner.
  def test_runs_again_a_nightly_whose_only_red_job_never_got_a_runner
    with_case("44093239386-1") do |server, runs|
      assert_equal :rerun, runs.call(44_093_239_386, 1).action
      assert_equal 1, posts(server).size
    end
  end

  # Run 44527956502: Build (arm64-darwin) never got a runner, and an
  # Android emulator job failed a step. The failure is real, so the run
  # stays as it is.
  def test_leaves_a_run_with_a_real_failure_beside_a_job_no_runner_took
    with_case("44527956502-1") do |server, runs|
      verdict = runs.call(44_527_956_502, 1)
      assert_equal :leave, verdict.action
      assert_includes verdict.reason, "Mobile apps (Android emulator"
      assert_empty posts(server)
    end
  end

  # Run 43869914706, the ruby/spec nightly of 2026-11-16: a job failed a
  # step on a runner.
  def test_leaves_a_run_whose_job_failed_a_step
    with_case("43869914706-1") do |server, runs|
      assert_equal :leave, runs.call(43_869_914_706, 1).action
      assert_empty posts(server)
    end
  end

  # Run 43482637885: Replace libcrypt (x86_64-linux) ran seven steps and
  # was cancelled when it passed its 15 minutes.
  def test_leaves_a_run_whose_job_ran_out_of_time
    with_case("43482637885-1") do |server, runs|
      verdict = runs.call(43_482_637_885, 1)
      assert_equal :leave, verdict.action
      assert_includes verdict.reason, "Replace libcrypt (x86_64-linux)"
      assert_empty posts(server)
    end
  end

  # Run 44529389886: waiting on trunk when a newer push replaced it, so
  # cancelled with no jobs at all. The newer run covers its commits.
  def test_leaves_a_run_a_newer_push_replaced
    with_case("44529389886-1") do |server, runs|
      assert_equal :leave, runs.call(44_529_389_886, 1).action
      assert_empty posts(server)
    end
  end

  # Run 43687329712: a person cancelled it, and its waiting jobs ended as
  # a job no runner took does, cancelled with no runner and no steps.
  def test_leaves_a_run_a_person_cancelled
    with_case("43687329712-1") do |server, runs|
      assert_equal :leave, runs.call(43_687_329_712, 1).action
      assert_empty posts(server)
    end
  end

  # A run cancelled as a whole, by a person or by a newer push, stays
  # cancelled, even with a job no runner took: here run 44536045262, as
  # if it had been cancelled.
  def test_leaves_a_cancelled_run_whatever_its_jobs
    with_case("44536045262-1", conclusion: "cancelled") do |server, runs|
      verdict = runs.call(44_536_045_262, 1)
      assert_equal :leave, verdict.action
      assert_includes verdict.reason, "cancelled"
      assert_empty posts(server)
    end
  end

  # Run 43137199420: trunk's concurrency group cancelled it while its jobs
  # waited, which ends a job as a job no runner took ends, but for the
  # annotation.
  def test_leaves_a_run_its_concurrency_group_cancelled
    with_case("43137199420-1") do |server, runs|
      assert_equal :leave, runs.call(43_137_199_420, 1).action
      assert_empty posts(server)
    end
  end

  # A job cancelled with no runner and no steps is runnerless only when
  # GitHub's annotation says so: here run 44536045262's job carries in
  # turn the annotation a job of run 43687329712 got when a person
  # cancelled it, and the one a job of run 43137199420 got when its
  # concurrency group cancelled it.
  def test_leaves_a_job_no_runner_took_only_when_github_says_so
    %w[43687329712-1 43137199420-1].each do |other|
      cancelled = JSON.parse(File.read(File.join(FIXTURES, "#{other}.json"))).fetch("annotations").values.first
      with_case("44536045262-1", annotations: { "135615174861" => cancelled }) do |server, runs|
        verdict = runs.call(44_536_045_262, 1)
        assert_equal :leave, verdict.action, other
        assert_includes verdict.reason, "Runtime (arm64-darwin)"
        assert_empty posts(server)
      end
    end
  end

  # Should GitHub ever give its annotation to a job that a runner took,
  # the job is still not run again: here run 44536045262's job, with the
  # annotation, carries in turn the runner, a step, and the conclusion of
  # the job of run 43482637885 that ran out of time.
  def test_leaves_a_job_that_got_a_runner_whatever_its_annotation_says
    timed_out = JSON.parse(File.read(File.join(FIXTURES, "43482637885-1.json"))).fetch("jobs").find { |job| job["name"].start_with?("Replace libcrypt") }
    [{ "runner_name" => timed_out.fetch("runner_name") }, { "steps" => timed_out.fetch("steps").first(1) }, { "conclusion" => "failure" }].each do |change|
      with_case("44536045262-1", job: { 135_615_174_861 => change }) do |server, runs|
        assert_equal :leave, runs.call(44_536_045_262, 1).action, change.keys.first
        assert_empty posts(server)
      end
    end
  end

  # A run that fails before any job starts, as one whose workflow GitHub
  # cannot read does, has no job to run again: here run 44529389886, with
  # no jobs, as if it had failed.
  def test_leaves_a_failed_run_with_no_red_job
    with_case("44529389886-1", conclusion: "failure") do |server, runs|
      verdict = runs.call(44_529_389_886, 1)
      assert_equal :leave, verdict.action
      assert_includes verdict.reason, "no red job"
      assert_empty posts(server)
    end
  end

  def test_leaves_a_run_that_was_run_again_since
    with_case("44536045262-1", attempt: 2) do |server, runs|
      verdict = runs.call(44_536_045_262, 1)
      assert_equal :leave, verdict.action
      assert_includes verdict.reason, "attempt 2"
      assert_empty posts(server)
    end
  end

  # A run that has needed GitHub's runner this often is not left to run
  # forever; a person looks at it.
  def test_leaves_a_run_that_has_been_run_again_enough
    attempt = RunnerlessRuns::ATTEMPTS
    with_case("44536045262-1", attempt:) do |server, runs|
      verdict = runs.call(44_536_045_262, attempt)
      assert_equal :leave, verdict.action
      assert_includes verdict.reason, "#{attempt} attempts"
      assert_empty posts(server)
    end
  end

  # Trunk's runs of CI share a concurrency group, in which GitHub keeps
  # one run going and one waiting, and a run queued again takes the
  # waiting one's place. A newer push's waiting run covers this run's
  # commits, so it is not replaced.
  def test_leaves_a_run_whose_rerun_would_replace_a_newer_run_waiting
    waiting = [{ id: 44_536_045_263, status: "pending" }]
    with_case("44536045262-1", waiting:) do |server, runs|
      verdict = runs.call(44_536_045_262, 1)
      assert_equal :leave, verdict.action
      assert_includes verdict.reason, "44536045263"
      assert_empty posts(server)
    end
  end

  def test_an_older_run_waiting_does_not_hold_a_run_back
    with_case("44536045262-1", waiting: [{ id: 44_536_045_000, status: "pending" }]) do |server, runs|
      assert_equal :rerun, runs.call(44_536_045_262, 1).action
      assert_equal 1, posts(server).size
    end
  end

  # With dry_run, it says what it would do and asks GitHub for nothing
  # but reads.
  def test_a_dry_run_changes_nothing
    with_case("44536045262-1", dry_run: true) do |server, runs|
      assert_equal :rerun, runs.call(44_536_045_262, 1).action
      assert_empty posts(server)
    end
  end

  # Serves the recorded answers of case +name+, changed only as the
  # keywords say: the run's +attempt+ and +conclusion+, the runs
  # +waiting+ in its group, a job's +annotations+, and fields of a +job+.
  # GitHub matches workflow_run's workflows by name, so a renamed
  # workflow would quietly lose its healing; and only trunk's runs are
  # run again, since on a branch a run queued again cancels the newer
  # run in progress there.
  def test_the_workflow_follows_ci_the_fast_tier_and_ruby_spec_on_trunk_only
    root = File.expand_path("..", __dir__)
    names = %w[ci.yml fast.yml fast-macos.yml ruby-spec.yml].map { |file| YAML.load_file(File.join(root, ".github/workflows", file), aliases: true).fetch("name") }
    trigger = YAML.load_file(File.join(root, ".github/workflows/runnerless.yml")).fetch(true).fetch("workflow_run")

    assert_equal names, trigger.fetch("workflows")
    assert_equal ["trunk"], trigger.fetch("branches")
    assert_equal ["completed"], trigger.fetch("types")
  end

  private def with_case(name, attempt: nil, conclusion: nil, waiting: [], dry_run: false, annotations: {}, job: {})
    recorded = JSON.parse(File.read(File.join(FIXTURES, "#{name}.json")))
    recorded["annotations"] = recorded.fetch("annotations").merge(annotations)
    run = recorded.fetch("run")
    run = run.merge("run_attempt" => attempt) if attempt
    run = run.merge("conclusion" => conclusion) if conclusion
    id = run.fetch("id")
    jobs = recorded.fetch("jobs").map { |each| each.merge(job.fetch(each.fetch("id"), {})) }
    routes = {
      "/repos/setdef/Fledge/actions/runs/#{id}" => [200, {}, JSON.generate(run)],
      "/repos/setdef/Fledge/actions/runs/#{id}/rerun-failed-jobs" => [201, {}, "{}"],
      waiting_path(run) => [200, {}, JSON.generate(total_count: waiting.size, workflow_runs: waiting)],
    }
    (jobs.empty? ? [[]] : jobs.each_slice(RunnerlessRuns::PER_PAGE)).each.with_index(1) do |page, number|
      routes[jobs_path(id, recorded.fetch("attempt"), number)] = [200, {}, JSON.generate(total_count: jobs.size, jobs: page)]
    end
    recorded.fetch("annotations").each do |job, annotations|
      routes["/repos/setdef/Fledge/check-runs/#{job}/annotations?per_page=#{RunnerlessRuns::PER_PAGE}&page=1"] = [200, {}, JSON.generate(annotations)]
    end
    server = LoopbackServer.new(routes)
    yield server, RunnerlessRuns.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0, dry_run:)
  ensure
    server&.stop
  end

  private def posts(server)
    server.calls.select { |call| call.start_with?("POST ") }
  end

  private def waiting_path(run)
    "/repos/setdef/Fledge/actions/workflows/#{run.fetch('workflow_id')}/runs?branch=#{run.fetch('head_branch')}&status=pending&per_page=#{RunnerlessRuns::PER_PAGE}&page=1"
  end

  private def jobs_path(id, attempt, page)
    "/repos/setdef/Fledge/actions/runs/#{id}/attempts/#{attempt}/jobs?per_page=#{RunnerlessRuns::PER_PAGE}&page=#{page}"
  end
end
