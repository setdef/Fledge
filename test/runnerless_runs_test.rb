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
# stays as red as it is. Each case is GitHub's own answer for a real run of this
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

  # GitHub's schema lets an annotation's message be null. Such an
  # annotation says nothing, so it neither hides GitHub's own annotation
  # beside it nor stands in for it: here run 44536045262's job carries
  # one before its recorded annotations, and then only that one.
  def test_an_annotation_with_no_message_says_nothing
    recorded = JSON.parse(File.read(File.join(FIXTURES, "44536045262-1.json"))).fetch("annotations").fetch("135615174861")
    silent = { "annotation_level" => "failure", "message" => nil }
    { [silent, *recorded] => :rerun, [silent] => :leave }.each do |annotations, action|
      with_case("44536045262-1", annotations: { "135615174861" => annotations }) do |_server, runs|
        assert_equal action, runs.call(44_536_045_262, 1).action
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

  # The workflow is started for trunk's own runs only, but a person can
  # start it by hand with any run, and the run is judged the same way:
  # here run 44536045262, as if it had been on a branch, and as if a
  # pull request from a branch named trunk had started it. A rerun on a
  # branch would cancel the newer run in progress there.
  def test_leaves_a_run_that_is_not_one_of_trunks_own
    [{ "head_branch" => "spike/macos" }, { "event" => "pull_request" }].each do |change|
      with_case("44536045262-1", run: change) do |server, runs|
        verdict = runs.call(44_536_045_262, 1)
        assert_equal :leave, verdict.action, change
        assert_includes verdict.reason, "trunk's own"
        assert_empty posts(server)
      end
    end
  end

  # The proof of a pin move runs ci.yml by dispatch on pin-move
  # (.github/scripts/pin-prove.sh asks for its rerun): here run
  # 44536045262 as such a run, and then as each thing that is not: a
  # push to pin-move, another workflow's dispatch, a branch of another
  # name. A run of pin-move that lost a runner runs again at once, since
  # no other run shares its group.
  def test_runs_again_the_proof_of_a_pin_move_and_no_other_run_of_that_branch
    proof = { "head_branch" => "pin-move", "event" => "workflow_dispatch" }
    with_case("44536045262-1", run: proof) do |server, runs|
      assert_equal :rerun, runs.call(44_536_045_262, 1).action
      assert_equal 1, posts(server).size
    end
    [{ "event" => "push" }, { "path" => ".github/workflows/fast.yml" }, { "head_branch" => "pin-move2" }].each do |change|
      with_case("44536045262-1", run: proof.merge(change)) do |server, runs|
        assert_equal :leave, runs.call(44_536_045_262, 1).action, change
        assert_empty posts(server)
      end
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
  # waiting one's place. Its second attempt and after have a group of
  # their own, named for the commit (ci.yml's concurrency, issue 75), so
  # a rerun replaces no newer push's run: here release run 44513751573
  # as if its commit's message were an ordinary one, beside a newer run
  # waiting in trunk's group (PENDING).
  def test_a_rerun_of_a_run_in_trunks_group_is_not_held_back_by_a_newer_run_waiting_there
    ordinary = { "head_commit" => { "message" => "docs: say what 0.14.0 left open" } }
    with_case("44513751573-1", run: ordinary, waiting: [pending]) do |server, runs|
      assert_equal :rerun, runs.call(44_513_751_573, 1).action
      assert_equal 1, posts(server).size
    end
  end

  # A run that waits in the group a rerun joins is one of the same
  # commit's, an attempt after its first or a dispatched run, and the
  # rerun would replace it: here PENDING as a second attempt of run
  # 44513751573's commit.
  def test_leaves_a_run_whose_rerun_would_replace_a_run_of_its_commit_waiting_in_its_group
    ordinary = { "head_commit" => { "message" => "docs: say what 0.14.0 left open" } }
    same = pending.merge("head_sha" => recorded_run("44513751573-1").fetch("head_sha"), "run_attempt" => 2)
    with_case("44513751573-1", run: ordinary, waiting: [same]) do |server, runs|
      verdict = runs.call(44_513_751_573, 1)
      assert_equal :leave, verdict.action
      assert_includes verdict.reason, pending.fetch("id").to_s
      assert_empty posts(server)
    end
  end

  # A release commit's run and a pin commit's each have a concurrency
  # group of their own, named for the commit (ci.yml, "Runs, batches, and
  # the release commit" in releases.md), so their rerun replaces nothing
  # waiting in trunk's: here release run 44513751573 as recorded, and as
  # if it were a pin commit's, beside a newer run waiting in trunk's
  # group (PENDING).
  def test_a_release_or_pin_commits_run_is_not_held_back_by_trunks_group
    [{}, { "head_commit" => { "message" => "chore: pin 0.14.0's runtimes" } }].each do |change|
      with_case("44513751573-1", run: change, waiting: [pending]) do |server, runs|
        assert_equal :rerun, runs.call(44_513_751_573, 1).action, change
        assert_equal 1, posts(server).size
      end
    end
  end

  # On trunk, every run of the fast tier has a group of its own commit,
  # so only a run of the same commit shares it: here run 44513751573 and
  # PENDING, both as if they were runs of fast.yml
  # and fast-macos.yml, and then as if both were of one commit.
  def test_a_fast_run_is_held_back_only_by_a_run_of_its_own_commit
    %w[fast.yml fast-macos.yml].each do |file|
      path = ".github/workflows/#{file}"
      same = pending.merge("path" => path, "head_sha" => recorded_run("44513751573-1").fetch("head_sha"))
      { pending.merge("path" => path) => :rerun, same => :leave }.each do |waiting, action|
        with_case("44513751573-1", run: { "path" => path }, waiting: [waiting]) do |_server, runs|
          assert_equal action, runs.call(44_513_751_573, 1).action, "#{file}, #{waiting.fetch('head_sha')}"
        end
      end
    end
  end

  # A pull request's run is in its pull request's group, even when its
  # head branch is a fork's trunk: here release run 44513751573 as if its
  # message were an ordinary one, beside PENDING as if a pull request had
  # started it.
  def test_a_pull_requests_run_waiting_does_not_hold_a_run_back
    ordinary = { "head_commit" => { "message" => "docs: say what 0.14.0 left open" } }
    with_case("44513751573-1", run: ordinary, waiting: [pending.merge("event" => "pull_request")]) do |server, runs|
      assert_equal :rerun, runs.call(44_513_751_573, 1).action
      assert_equal 1, posts(server).size
    end
  end

  # Run 44536045262 beside run 44527956502 of trunk's group, recorded,
  # as if it were waiting: an older run waiting is no newer push.
  def test_an_older_run_waiting_does_not_hold_a_run_back
    older = recorded_run("44527956502-1").merge("status" => "pending")
    with_case("44536045262-1", waiting: [older]) do |server, runs|
      assert_equal :rerun, runs.call(44_536_045_262, 1).action
      assert_equal 1, posts(server).size
    end
  end

  # ruby/spec's workflow has no concurrency group, so nothing waits in
  # one for its rerun to replace, and nothing is asked about it.
  def test_a_run_with_no_concurrency_group_asks_for_no_waiting_run
    with_case("44093239386-1") do |server, runs|
      assert_equal :rerun, runs.call(44_093_239_386, 1).action
      assert_empty(server.requests.grep(/status=pending/))
    end
  end

  # A workflow this does not know the group of may share one with
  # anything, so its run is left: here run 44536045262, as if it were a
  # run of a workflow added later.
  def test_leaves_a_run_whose_concurrency_group_it_does_not_know
    with_case("44536045262-1", run: { "path" => ".github/workflows/nightly.yml" }) do |server, runs|
      verdict = runs.call(44_536_045_262, 1)
      assert_equal :leave, verdict.action
      assert_includes verdict.reason, "nightly.yml"
      assert_empty posts(server)
    end
  end

  # RunnerlessRuns reads each run's concurrency group from what the API
  # says of it, since the API names none, so it holds a copy of each
  # followed workflow's concurrency block. A change to a block fails here
  # until RunnerlessRuns#group reads the new one.
  def test_it_knows_the_concurrency_group_of_every_workflow_it_follows
    trunk_group = "${{ github.workflow }}-${{ github.ref }}-${{ github.ref == format('refs/heads/{0}', github.event.repository.default_branch) && github.sha || 'branch' }}"
    groups = {
      "ci.yml" => "${{ github.workflow }}-${{ github.ref }}${{ (startsWith(github.event.head_commit.message, 'chore: release ') || startsWith(github.event.head_commit.message, 'chore: pin ') || (github.ref == format('refs/heads/{0}', github.event.repository.default_branch) && (github.event_name == 'workflow_dispatch' || github.run_attempt != '1'))) && format('-{0}', github.sha) || '' }}",
      "fast.yml" => trunk_group,
      "fast-macos.yml" => trunk_group,
      "ruby-spec.yml" => nil,
    }
    groups.each do |file, group|
      concurrency = YAML.load_file(File.join(File.expand_path("..", __dir__), ".github/workflows", file), aliases: true)["concurrency"]
      group ? assert_equal(group, concurrency.fetch("group"), file) : assert_nil(concurrency, file)
    end
    assert_equal ["chore: release ", "chore: pin "], RunnerlessRuns::OWN_GROUP
  end

  # With dry_run, it says what it would do and asks GitHub for nothing
  # but reads.
  def test_a_dry_run_changes_nothing
    with_case("44536045262-1", dry_run: true) do |server, runs|
      assert_equal :rerun, runs.call(44_536_045_262, 1).action
      assert_empty posts(server)
    end
  end

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

  # Serves the recorded answers of case +name+, changed only as the
  # keywords say: the run's +attempt+ and +conclusion+, other fields of
  # the +run+, the runs +waiting+ on its branch, a job's +annotations+,
  # and fields of a +job+.
  private def with_case(name, attempt: nil, conclusion: nil, run: {}, waiting: [], dry_run: false, annotations: {}, job: {})
    recorded = JSON.parse(File.read(File.join(FIXTURES, "#{name}.json")))
    recorded["annotations"] = recorded.fetch("annotations").merge(annotations)
    run = recorded.fetch("run").merge(run)
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

  private def recorded_run(name)
    JSON.parse(File.read(File.join(FIXTURES, "#{name}.json"))).fetch("run")
  end

  # A newer run of CI waiting in trunk's concurrency group beside release
  # run 44513751573 (PENDING below). No run waited beside it when its
  # first attempt ended, as GitHub's API lists trunk's runs of that day,
  # so this is recorded run 44527956502 of trunk's group, pushed after
  # it, with only its status and conclusion changed to a waiting run's.
  private def pending
    JSON.parse(File.read(File.join(FIXTURES, "pending-beside-44513751573-1.json"))).fetch("run")
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
