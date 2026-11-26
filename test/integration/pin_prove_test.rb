# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "json"
require_relative "../support/loopback_server"
require_relative "../../tasks/runnerless_runs"

# What .github/scripts/pin-prove.sh reports once a proven move is on
# trunk (doc/contributors/design/runtimes.md, "The proof"), run as the
# workflow runs it, with real git and a real bare origin, and only the
# two things that need GitHub or the pins' upstreams standing in: gh,
# which answers each run of ci.yml with the conclusion the test gives
# it, and the move itself, which changes one file.
#
# A test takes two to six seconds, and no more can be cut without
# changing what the script does. The script's waits are set to nothing
# (PIN_PROVE_START_TRIES, PIN_PROVE_START_SECONDS, and
# PIN_PROVE_RUN_SECONDS), the repositories are copied from ones made
# once, and the gh stand-in uses shell builtins. What is left is the
# script's commands: a proof that lands a move runs about fifteen
# git commands, a commit and a push among them, and each takes between a
# tenth and a quarter of a second on a Mac, as a process start does
# (bash, jq, and Ruby for the rerun task take a twentieth to a tenth).
# The test that proves a move once for each of two kinds of head runs
# the script twice, and takes twice that.
class PinProveTest < Minitest::Test
  SCRIPT = File.expand_path("../../.github/scripts/pin-prove.sh", __dir__)

  def test_a_move_rebased_onto_a_red_trunk_has_landed_and_its_job_is_green
    result = prove(trunk_run: "completed failure")

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:summary], "Landed, and not released"
    assert_includes result[:summary], "actions/runs/2"
    assert_includes result[:output], "proven=true"
    refute_match(/^landed=/, result[:output], "a red trunk is not offered to the release")
    assert_equal "changed", result[:trunk_version]
  end

  def test_a_move_rebased_onto_a_green_trunk_has_landed_and_is_offered_to_the_release
    result = prove(trunk_run: "completed success")

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:summary], "Green on trunk"
    assert_match(/^landed=\h{40}$/, result[:output])
    assert_match(/^release=\h{40}$/, result[:output])
    assert_equal "changed", result[:trunk_version]
  end

  def test_a_red_proof_fails_the_job_and_lands_nothing
    result = prove(branch_run: "completed failure", trunk_run: "completed success")

    assert_equal 1, result[:status]
    assert_includes result[:output], "proven=false"
    assert_equal "base", result[:trunk_version]
  end

  # A push that landed between the proof and the dispatch leaves trunk's
  # head a later commit than the move's, and the run takes that head.
  # The move is judged by the run the dispatch started. When that run is
  # green and its head holds the move, the head is what the release
  # takes: a trunk commit that holds the move, and whose own run passed
  # every job.
  def test_a_green_run_of_a_later_head_that_holds_the_move_offers_that_head_to_the_release
    result = prove(trunk_run: "completed success", trunk_list: :descends)
    head = result[:later]

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:summary], "actions/runs/2"
    assert_includes result[:summary], "#{head}, a later commit that holds the move"
    assert_includes result[:output], "release=#{head}\n"
    refute_match(/^landed=/, result[:output], "landed is the move's commit, whose own run did not judge it")
    assert_equal "changed", result[:trunk_version]
  end

  # A green run of a commit that does not hold the move judges nothing
  # about it: a commit before it, or one git does not have.
  def test_a_green_run_of_a_head_that_does_not_hold_the_move_offers_nothing
    %i[ancestor unknown].each do |kind|
      result = prove(trunk_run: "completed success", trunk_list: kind)

      assert_equal 0, result[:status], result[:stderr]
      assert_includes result[:summary], "Landed, and not released"
      assert_includes result[:summary], "does not hold the move"
      assert_includes result[:stdout], "::warning::"
      refute_match(/^(release|landed)=/, result[:output], kind.to_s)
      assert_equal "changed", result[:trunk_version]
    end
  end

  def test_a_red_run_of_a_later_head_offers_nothing
    result = prove(trunk_run: "completed failure", trunk_list: :descends)

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:summary], "Landed, and not released"
    refute_match(/^(release|landed)=/, result[:output])
  end

  def test_a_run_of_the_landed_commit_is_offered_as_the_commit_to_release
    result = prove(trunk_run: "completed success")

    refute_includes result[:summary], "a later commit"
    assert_match(/^release=\h{40}$/, result[:output])
    assert_equal result[:output][/^landed=(\h{40})$/, 1], result[:output][/^release=(\h{40})$/, 1]
  end

  # A move that is on trunk, with no run of ci.yml found for it, has
  # landed all the same: follow returns, and the script ends green.
  def test_a_move_landed_on_trunk_with_no_run_found_ends_green
    result = prove(trunk_run: "completed success", trunk_list: :none)

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:summary], "Landed, and not released"
    assert_includes result[:output], "proven=true"
    refute_match(/^landed=/, result[:output])
    assert_equal "changed", result[:trunk_version]
  end

  # The run the dispatch started is one created after it: a dispatch
  # from before it, someone else's, is no answer.
  def test_a_dispatched_run_from_before_the_dispatch_is_no_run
    result = prove(trunk_run: "completed success", trunk_list: :stale)

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:summary], "Landed, and not released"
    refute_match(/^landed=/, result[:output])
  end

  # Before it lands, a missing run is the proof's failure.
  def test_a_proof_whose_run_never_starts_fails_the_job_and_lands_nothing
    result = prove(trunk_run: "completed success", branch_list: :none)

    assert_equal 1, result[:status]
    assert_includes result[:stdout], "No run of ci.yml started"
    assert_equal "base", result[:trunk_version]
  end

  # A run that loses a runner has not failed: the script asks
  # tasks/runnerless_runs.rb, which reads GitHub's answers for the run
  # (the recorded ones of test/fixtures/runnerless, served on the
  # loopback), and when every red job never got a runner, runs the failed
  # jobs again and judges the new attempt.
  def test_a_proof_whose_only_red_jobs_never_got_a_runner_is_run_again_and_judged_by_the_rerun
    result = prove(branch_run: ["completed failure", "completed success"], causes: [:runnerless])

    assert_equal 0, result[:status], result[:stderr]
    assert_equal ["POST /repos/setdef/Fledge/actions/runs/1/rerun-failed-jobs"], result[:reruns][1]
    assert_includes result[:summary], "Ran its failed jobs again"
    assert_includes result[:output], "proven=true"
    assert_equal "changed", result[:trunk_version]
  end

  def test_a_proof_with_a_real_failure_is_red_with_no_rerun
    result = prove(branch_run: "completed failure", causes: [:real])

    assert_equal 1, result[:status]
    assert_empty result[:reruns][1]
    assert_includes result[:output], "proven=false"
    assert_equal "base", result[:trunk_version]
  end

  def test_a_proof_that_loses_a_runner_on_every_attempt_is_red_after_two_reruns
    result = prove(branch_run: ["completed failure"] * 3, causes: [:runnerless] * 3)

    assert_equal 1, result[:status]
    assert_equal 2, result[:reruns][1].size
    assert_includes result[:output], "proven=false"
    assert_equal "base", result[:trunk_version]
  end

  # runnerless.yml, or a person, may run the failed jobs again before the
  # script asks: the task then finds the run "on attempt 2 now", and
  # leaves it. The script waits for that attempt and judges it as it
  # judges one it started.
  def test_a_proof_someone_else_ran_again_is_judged_by_the_newest_attempt
    result = prove(branch_run: ["completed failure", "completed success"], causes: [:runnerless], others: [1])

    assert_equal 0, result[:status], result[:stderr]
    assert_empty result[:reruns][1]
    assert_includes result[:output], "proven=true"
    assert_equal "changed", result[:trunk_version]
  end

  def test_a_proof_someone_else_ran_again_that_is_red_is_judged_red
    result = prove(branch_run: ["completed failure"] * 2, causes: [:real], others: [1])

    assert_equal 1, result[:status]
    assert_empty result[:reruns][1]
    assert_includes result[:output], "proven=false"
    assert_equal "base", result[:trunk_version]
  end

  # The two reruns are of the run, whoever starts them: one attempt of
  # someone else's leaves the script one.
  def test_the_cap_of_two_reruns_counts_the_attempts_someone_else_started
    result = prove(branch_run: ["completed failure"] * 3, causes: [:runnerless] * 3, others: [1])

    assert_equal 1, result[:status]
    assert_equal 1, result[:reruns][1].size
    assert_includes result[:output], "proven=false"
    assert_equal "base", result[:trunk_version]
  end

  # A real failure beside a job no runner took leaves the run red.
  def test_a_proof_with_a_real_failure_beside_a_job_no_runner_took_is_not_run_again
    result = prove(branch_run: "completed failure", causes: [:both])

    assert_equal 1, result[:status]
    assert_empty result[:reruns][1]
  end

  # The run on trunk that judges a rebased move is waited for the same
  # way.
  def test_a_run_on_trunk_that_loses_a_runner_is_run_again_and_judged_by_the_rerun
    result = prove(trunk_run: ["completed failure", "completed success"], trunk_causes: [:runnerless])

    assert_equal 0, result[:status], result[:stderr]
    assert_equal ["POST /repos/setdef/Fledge/actions/runs/2/rerun-failed-jobs"], result[:reruns][2]
    assert_includes result[:summary], "Green on trunk"
    assert_match(/^release=\h{40}$/, result[:output])
  end

  # The recorded answers of GitHub for a red run, by cause: a job that
  # never got a runner (run 44536045262), a job that ran a step and
  # failed (run 43869914706), and both (run 44527956502).
  CAUSES = { runnerless: "44536045262-1", real: "43869914706-1", both: "44527956502-1" }.freeze
  FIXTURES = File.expand_path("../fixtures/runnerless", __dir__)
  TASK = File.expand_path("../../tasks/runnerless_runs.rb", __dir__)

  # The runs gh lists for the dispatch whose number is the key, as JSON,
  # where HERE stands for the commit checked out when gh is asked.
  RUN_LISTS = {
    own: '[{"databaseId":%d,"headSha":"HERE","createdAt":"2099-01-01T00:00:00Z"}]',
    descends: '[{"databaseId":%d,"headSha":"LATER","createdAt":"2099-01-01T00:00:00Z"}]',
    ancestor: '[{"databaseId":%d,"headSha":"ANCESTOR","createdAt":"2099-01-01T00:00:00Z"}]',
    unknown: "[{\"databaseId\":%d,\"headSha\":\"#{'f' * 40}\",\"createdAt\":\"2099-01-01T00:00:00Z\"}]",
    stale: '[{"databaseId":%d,"headSha":"HERE","createdAt":"2000-01-01T00:00:00Z"}]',
    none: "[]",
  }.freeze

  private def prove(trunk_run: "completed success", branch_run: "completed success", trunk_list: :own, branch_list: :own, causes: [:real], trunk_causes: [:real], others: [])
    Dir.mktmpdir do |dir|
      work = File.join(dir, "work")
      checkout = File.join(dir, "checkout")
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      copy_repositories(dir)
      write_shims(bin, dir, work)
      server = github({ 1 => [branch_run, causes, "pin-move"], 2 => [trunk_run, trunk_causes, "trunk"] }, dir)
      others.each { |number| FileUtils.touch(File.join(dir, "other-#{number}")) }
      { 1 => branch_list, 2 => trunk_list }.each { |number, kind| File.write(File.join(dir, "list-#{number}.json"), RUN_LISTS.fetch(kind).gsub("%d", number.to_s)) }
      env = {
        "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
        "GITHUB_OUTPUT" => File.join(dir, "output"),
        "GITHUB_STEP_SUMMARY" => File.join(dir, "summary"),
        "GITHUB_SERVER_URL" => "https://github.test",
        "GITHUB_REPOSITORY" => "setdef/Fledge",
        "GITHUB_API_URL" => server.url(""),
        "GH_TOKEN" => "secret",
        "PIN_PROVE_START_TRIES" => "2",
        "PIN_PROVE_START_SECONDS" => "0",
        "PIN_PROVE_RUN_SECONDS" => "0",
      }
      FileUtils.touch([env["GITHUB_OUTPUT"], env["GITHUB_STEP_SUMMARY"]])
      out, err, status = Open3.capture3(env, "bash", SCRIPT, "report.json", chdir: checkout)
      git(work, "pull", "--quiet", "origin", "trunk")
      {
        later: File.exist?(File.join(dir, "later-sha")) ? File.read(File.join(dir, "later-sha")).strip : nil,
        status: status.exitstatus,
        stderr: err,
        stdout: out,
        summary: File.read(env["GITHUB_STEP_SUMMARY"]),
        output: File.read(env["GITHUB_OUTPUT"]),
        trunk_version: File.read(File.join(work, "version")).strip,
        reruns: [1, 2].to_h { |run| [run, server.calls.grep(%r{\APOST .*/runs/#{run}/rerun-failed-jobs\z})] },
      }
    ensure
      server&.stop
    end
  end

  # The repositories every test starts from, made once with real git:
  # a bare origin whose trunk holds a base commit and one that landed
  # after the checkout was cloned, the clone a test's work runs in (at
  # the base), and a clone that pushes the later commits. Git takes
  # about a tenth of a second a command here, so a test copies them
  # (each remote's path rewritten to the copy's) where building them took
  # nearly two seconds of its time.
  def self.repositories
    @repositories ||= Dir.mktmpdir.tap do |root|
      Minitest.after_run { FileUtils.rm_rf(root) }
      work = File.join(root, "work")
      git_in(root, "init", "--quiet", "--bare", "-b", "trunk", File.join(root, "origin.git"))
      git_in(root, "clone", "--quiet", File.join(root, "origin.git"), work)
      File.write(File.join(work, ".gitignore"), "tmp/\n")
      write_commit(work, "version", "base")
      git_in(work, "push", "--quiet", "origin", "HEAD:trunk")
      git_in(root, "clone", "--quiet", File.join(root, "origin.git"), File.join(root, "checkout"))
      write_commit(work, "other", "landed meanwhile")
      git_in(work, "push", "--quiet", "origin", "HEAD:trunk")
      File.write(File.join(root, "ancestor-sha"), git_in(work, "rev-parse", "HEAD"))
    end
  end

  def self.git_in(dir, *)
    out, status = Open3.capture2e("git", *, chdir: dir)
    raise out unless status.success?

    out
  end

  def self.write_commit(dir, file, text)
    File.write(File.join(dir, file), "#{text}\n")
    git_in(dir, "add", "--all")
    git_in(dir, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m", text)
  end

  private def copy_repositories(dir)
    root = self.class.repositories
    FileUtils.cp_r(File.join(root, "."), dir)
    %w[work checkout].each do |name|
      config = File.join(dir, name, ".git", "config")
      File.write(config, File.read(config).gsub(root, dir))
    end
  end

  # GitHub's API on the loopback, for each run of ci.yml the shim of gh
  # starts (number 1 on pin-move, 2 on trunk): +outcomes+ gives, for
  # each, the conclusion of each attempt (a line of the file outcome-N,
  # which the shim reads), the cause of each red attempt's red jobs, and
  # the branch. The answers are the recorded ones, with the run's own
  # fields. A POST that runs the failed jobs again makes the next
  # attempt the current one.
  private def github(outcomes, dir)
    routes = {}
    outcomes.each do |run, (conclusions, causes, branch)|
      conclusions = Array(conclusions)
      File.write(File.join(dir, "outcome-#{run}"), conclusions.map { |each| "#{each}\n" }.join)
      FileUtils.touch(File.join(dir, "reruns-#{run}"))
      attempt = -> { File.readlines(File.join(dir, "reruns-#{run}")).size + 1 }
      recorded = causes.map { |cause| JSON.parse(File.read(File.join(FIXTURES, "#{CAUSES.fetch(cause)}.json"))) }
      cause = -> { recorded.fetch([attempt.call, recorded.size].min - 1) }
      routes["/repos/setdef/Fledge/actions/runs/#{run}/rerun-failed-jobs"] = lambda {
        File.write(File.join(dir, "reruns-#{run}"), "rerun\n", mode: "a")
        [201, {}, "{}"]
      }
      routes["/repos/setdef/Fledge/actions/runs/#{run}"] = lambda {
        fields = {
"id" => run,
"head_branch" => branch,
"event" => "workflow_dispatch",
"path" => ".github/workflows/ci.yml",
"status" => "completed",
"conclusion" => "failure",
"run_attempt" => attempt.call,
}
        [200, {}, JSON.generate(cause.call.fetch("run").merge(fields))]
      }
      routes["/repos/setdef/Fledge/actions/workflows/396724957/runs?branch=#{branch}&status=pending&per_page=#{RunnerlessRuns::PER_PAGE}&page=1"] =
        [200, {}, JSON.generate(total_count: 0, workflow_runs: [])]
      (1..3).each do |number|
        routes["/repos/setdef/Fledge/actions/runs/#{run}/attempts/#{number}/jobs?per_page=#{RunnerlessRuns::PER_PAGE}&page=1"] = lambda {
          jobs = cause.call.fetch("jobs")
          [200, {}, JSON.generate(total_count: jobs.size, jobs:)]
        }
      end
      recorded.flat_map { |each| each.fetch("annotations").to_a }.each do |job, annotations|
        routes["/repos/setdef/Fledge/check-runs/#{job}/annotations?per_page=#{RunnerlessRuns::PER_PAGE}&page=1"] = [200, {}, JSON.generate(annotations)]
      end
    end
    LoopbackServer.new(routes)
  end

  private def write_shims(bin, dir, work)
    shim(bin, "ruby", <<~SH)
      if [ "$1" = tasks/runnerless_runs.rb ]; then shift; exec #{RbConfig.ruby} #{TASK} "$@"; fi
      echo changed > version
      printf 'chore: move zlib\\n' > "$4"
      echo "moved zlib"
    SH
    shim(bin, "bundle", ": # rake licensing")
    # Builtins only where they can be: each process is a tenth of a
    # second here, and the script asks gh for every look at a run.
    shim(bin, "gh", <<~SH)
      attempt_of() { a=1; while read -r _; do a=$((a + 1)); done < #{dir}/reruns-$1; }
      case "$1 $2" in
        "workflow run")
          n=0; [ -e #{dir}/runs ] && n=$(<#{dir}/runs); n=$((n + 1)); echo $n > #{dir}/runs
          # A push that lands between the move's and the dispatch, which
          # the run then takes as its head.
          if [ $n = 2 ] && [[ $(<#{dir}/list-2.json) == *LATER* ]]; then
            git -C #{work} pull --quiet origin trunk
            echo later > #{work}/later
            git -C #{work} add --all
            git -C #{work} -c user.name=t -c user.email=t@example.com commit --quiet -m "landed after the move"
            git -C #{work} push --quiet origin HEAD:trunk
            git -C #{work} rev-parse HEAD > #{dir}/later-sha
          fi ;;
        "run list")
          expr=.; commit=
          while [ $# -gt 0 ]; do
            case "$1" in --jq) expr=$2 ;; --commit) commit=$2 ;; esac
            shift
          done
          list=$(<#{dir}/list-$(<#{dir}/runs).json)
          later=; [ -e #{dir}/later-sha ] && later=$(<#{dir}/later-sha)
          list=${list//HERE/$(git rev-parse HEAD)}; list=${list//LATER/$later}; list=${list//ANCESTOR/$(<#{dir}/ancestor-sha)}
          echo "$list" | jq -r --arg c "$commit" 'map(select($c == "" or .headSha == $c)) | '"$expr" ;;
        "run view")
          n=$(<#{dir}/runs); attempt_of $n
          case "$*" in
            *status,conclusion*)
              line=; i=0
              while read -r each; do i=$((i + 1)); if [ $i = $a ]; then line=$each; fi; done < #{dir}/outcome-$n
              line=${line:-completed failure}
              case "$*" in *conclusion,attempt*) echo "$line $a" ;; *) echo "$line" ;; esac
              # Someone else runs the failed jobs again once this answer is given.
              if [ -e #{dir}/other-$n ]; then rm #{dir}/other-$n; echo rerun >> #{dir}/reruns-$n; fi ;;
            *json\\ attempt*) echo $a ;;
          esac ;;
      esac
    SH
  end

  private def shim(bin, name, body)
    path = File.join(bin, name)
    File.write(path, "#!/usr/bin/env bash\n#{body}")
    File.chmod(0o755, path)
  end

  private def git(dir, *)
    out, status = Open3.capture2e("git", *, chdir: dir)
    assert status.success?, out
    out
  end
end
