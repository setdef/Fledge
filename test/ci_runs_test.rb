# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/loopback_server"
require_relative "../tasks/ci_runs"
require "json"

# How release.yml, and rake runtime:pin, learn that a commit passed CI
# on trunk without running CI again (ADR 053): GitHub's REST API, served
# here by a loopback server that answers as GitHub's does, read through
# Net::HTTP itself.
class CIRunsTest < Minitest::Test
  SHA = "0123456789abcdef0123456789abcdef01234567"

  def test_finds_the_run_whose_every_job_passed
    with_api(runs: [a_run(7)], jobs: { 7 => [a_job("Gate"), a_job("Build (arm64-darwin)")] }) do |server, runs|
      assert_equal 7, runs.green(SHA)
      assert_equal ["Bearer secret"], server.authorizations.uniq
    end
  end

  # A pin-only commit's CI skips the jobs a pin cannot change (ADR 053;
  # doc/contributors/design/releases.md, "A pin commit's short CI"), so
  # a skipped job counts unless every job has to have run.
  def test_skipped_jobs_count_only_when_every_job_need_not_have_run
    with_api(runs: [a_run(7)], jobs: { 7 => [a_job("Gate"), a_job("Build (arm64-darwin)", "skipped")] }) do |_, runs|
      assert_equal 7, runs.green(SHA)

      error = assert_raises(CIRuns::NotGreen) { runs.green(SHA, skipped: false) }
      assert_includes error.message, "Build (arm64-darwin): skipped"
    end
  end

  def test_refuses_a_run_with_a_failed_job_and_names_the_run_and_the_job
    with_api(runs: [a_run(7)], jobs: { 7 => [a_job("Gate"), a_job("Replace libcrypt (x86_64-linux)", "failure")] }) do |_, runs|
      error = assert_raises(CIRuns::NotGreen) { runs.green(SHA) }
      assert_includes error.message, "https://github.com/setdef/Fledge/actions/runs/7"
      assert_includes error.message, "Replace libcrypt (x86_64-linux): failure"
      refute_includes error.message, "Gate"
    end
  end

  def test_refuses_a_run_that_has_not_finished
    with_api(runs: [a_run(7, status: "in_progress", conclusion: nil)], jobs: { 7 => [a_job("Gate", nil, status: "in_progress")] }) do |_, runs|
      error = assert_raises(CIRuns::NotGreen) { runs.green(SHA) }
      assert_includes error.message, "actions/runs/7"
      assert_includes error.message, "in_progress"
    end
  end

  # A commit inside a batch has no run of its own (ADR 071), so the
  # message says how a commit gets one.
  def test_refuses_a_commit_with_no_run_on_a_push_to_the_branch
    with_api(runs: [], jobs: {}) do |_, runs|
      error = assert_raises(CIRuns::NotGreen) { runs.green(SHA) }
      assert_includes error.message, SHA
      assert_includes error.message, "no run of ci.yml on a push to trunk"
      assert_includes error.message, "push it alone, as the head of its push"
    end
  end

  # A run whose failed jobs were run again is green when their latest
  # attempts passed: GitHub's filter=latest gives each job's newest
  # attempt, which is the only answer the server here gives.
  def test_takes_each_jobs_latest_attempt_in_a_run_that_was_run_again
    with_api(runs: [a_run(7, attempt: 2)], jobs: { 7 => [a_job("Gate"), a_job("Runtime (ios)")] }) do |_, runs|
      assert_equal 7, runs.green(SHA)
    end
  end

  # Runs come newest first. A commit is tested once any of its runs is
  # green; of two green runs, the newest one's runtimes are the pinned
  # ones, as rake runtime:pin picks it.
  def test_takes_the_newest_green_run_of_several
    jobs = { 9 => [a_job("Gate", "cancelled")], 8 => [a_job("Gate")], 7 => [a_job("Gate")] }
    with_api(runs: [a_run(9, conclusion: "cancelled"), a_run(8), a_run(7)], jobs:) do |_, runs|
      assert_equal 8, runs.green(SHA)
    end
  end

  def test_reads_every_page_of_a_runs_jobs
    jobs = Array.new(CIRuns::PER_PAGE) { |index| a_job("Licenses (#{index})") } + [a_job("Delivery (x64-mingw-ucrt)", "failure")]
    with_api(runs: [a_run(7)], jobs: { 7 => jobs }) do |_, runs|
      error = assert_raises(CIRuns::NotGreen) { runs.green(SHA) }
      assert_includes error.message, "Delivery (x64-mingw-ucrt): failure"
    end
  end

  def test_says_what_the_api_answered_when_it_refuses
    server = LoopbackServer.new
    runs = CIRuns.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0)
    error = assert_raises(CIRuns::Error) { runs.green(SHA) }
    assert_includes error.message, "404"
    assert_equal 1, server.requests.size
  ensure
    server&.stop
  end

  # GitHub's API answers 502 now and then; on 2026-11-03 it did for
  # every jobs request of run 41596806895 at 100 a page, and not at 50.
  def test_asks_again_when_the_api_fails_on_its_side
    answers = [[502, {}, '{"message": "Server Error"}'], [200, {}, JSON.generate(total_count: 1, workflow_runs: [a_run(7)])]]
    server = LoopbackServer.new(runs_path => -> { (answers.size > 1) ? answers.shift : answers.first }, jobs_path(7, 1) => [200, {}, JSON.generate(total_count: 1, jobs: [a_job("Gate")])])
    runs = CIRuns.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0)
    assert_equal 7, runs.green(SHA)
  ensure
    server&.stop
  end

  def test_gives_up_when_the_api_keeps_failing_on_its_side
    server = LoopbackServer.new(runs_path => [503, {}, "unavailable"])
    runs = CIRuns.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0)
    error = assert_raises(CIRuns::Error) { runs.green(SHA) }
    assert_includes error.message, "503"
    assert_equal CIRuns::ATTEMPTS, server.requests.size
  ensure
    server&.stop
  end

  private def with_api(runs:, jobs:)
    routes = { runs_path => [200, {}, JSON.generate(total_count: runs.size, workflow_runs: runs)] }
    jobs.each do |id, list|
      list.each_slice(CIRuns::PER_PAGE).with_index(1) do |page, number|
        routes[jobs_path(id, number)] = [200, {}, JSON.generate(total_count: list.size, jobs: page)]
      end
    end
    server = LoopbackServer.new(routes)
    yield server, CIRuns.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0)
  ensure
    server&.stop
  end

  private def runs_path
    "/repos/setdef/Fledge/actions/workflows/ci.yml/runs?head_sha=#{SHA}&branch=trunk&event=push&per_page=#{CIRuns::PER_PAGE}&page=1"
  end

  private def jobs_path(id, page)
    "/repos/setdef/Fledge/actions/runs/#{id}/jobs?filter=latest&per_page=#{CIRuns::PER_PAGE}&page=#{page}"
  end

  private def a_run(id, status: "completed", conclusion: "success", attempt: 1)
    { id:, html_url: "https://github.com/setdef/Fledge/actions/runs/#{id}", head_sha: SHA, status:, conclusion:, run_attempt: attempt }
  end

  private def a_job(name, conclusion = "success", status: "completed")
    { name:, status:, conclusion: }
  end
end
