# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "github_api"

# Runs again the failed jobs of a run on trunk that is red only because
# GitHub never gave a job a runner.
#
# GitHub's hosted runners run out now and then, macOS arm64's most of
# all. A job that waits too long is cancelled with no runner, no steps,
# no log, and the annotation "The job was not acquired by Runner of
# type hosted even after multiple attempts". The jobs that need it are
# skipped, and the run is red until a person runs its failed jobs
# again, though nothing in it failed. A release waits on it too, since
# release.yml publishes only from a run that passed.
#
# This class tells such a run apart from every other red run, and asks
# GitHub to run its failed jobs again, as <tt>gh run rerun --failed</tt>
# does. It never does so for a run in which any job ran a step and
# failed, or was cancelled for another reason, so a real failure stays
# exactly as red as it is (doc/contributors/design/releases.md, "A job
# no runner took"), nor for any run but trunk's own, whoever asks.
# .github/workflows/runnerless.yml calls it when a run of CI, Fast,
# Fast (macOS), or ruby/spec on trunk ends red.
#
#   ruby tasks/runnerless_runs.rb RUN ATTEMPT [--dry-run]
#
# prints what it did, or with --dry-run what it would do, and why. It
# reads GITHUB_REPOSITORY, GITHUB_API_URL, and GH_TOKEN or GITHUB_TOKEN,
# as a workflow's steps have them.
class RunnerlessRuns
  # What to do with a run, and why: +action+ is :rerun or :leave.
  class Verdict < Data.define(:action, :reason); end

  # The only branch whose runs are run again. On any other, a run queued
  # again would cancel the newer run in progress there, and so would a
  # pull request's run, whose head branch may be a fork's trunk.
  BRANCH = "trunk"

  # How the message of a commit starts whose push gets a concurrency
  # group of its own in ci.yml: a release commit's and a pin commit's.
  OWN_GROUP = ["chore: release ", "chore: pin "].freeze

  # Items asked for on each page of the API's answers.
  PER_PAGE = GitHubAPI::PER_PAGE

  # The annotation GitHub gives a job it cancelled because no runner
  # took it.
  NOT_ACQUIRED = "The job was not acquired by Runner of type hosted"

  # The attempts a run may have before it is left for a person: this
  # class runs a run's failed jobs again at most twice.
  ATTEMPTS = 3

  # Jobs whose conclusion makes a run red.
  PASSED = %w[success skipped neutral].freeze

  # +pause+ is the seconds to wait before repeating a request GitHub
  # failed on its side. With +dry_run+, nothing is asked of GitHub but
  # reads.
  def initialize(repository:, token:, api: "https://api.github.com", pause: 5, dry_run: false)
    @github = GitHubAPI.new(repository:, token:, api:, pause:)
    @dry_run = dry_run
  end

  # Decides what to do with attempt +attempt+ of run +id+, runs its failed
  # jobs again when every one of them never got a runner, and returns the
  # Verdict.
  def call(id, attempt)
    verdict = judge(@github.get("actions/runs/#{id}"), attempt)
    @github.post("actions/runs/#{id}/rerun-failed-jobs") if verdict.action == :rerun && !@dry_run
    verdict
  end

  private def judge(run, attempt)
    branch, event = run.values_at("head_branch", "event")
    return leave("it is a #{event} run of #{branch}, not one of #{BRANCH}'s own") unless branch == BRANCH && event != "pull_request"

    latest = run.fetch("run_attempt")
    return leave("it is on attempt #{latest} now, not #{attempt}") unless latest == attempt
    return leave("it has had #{attempt} attempts, as many as this runs") if attempt >= ATTEMPTS
    return leave("it is #{run['status']}, #{run['conclusion'].inspect}, not a completed failure") unless run.values_at("status", "conclusion") == %w[completed failure]

    red = @github.all("actions/runs/#{run.fetch('id')}/attempts/#{attempt}/jobs", "jobs").reject { |job| PASSED.include?(job["conclusion"]) }
    return leave("it has no red job") if red.empty?

    real = red.reject { |job| runnerless?(job) }
    return leave("#{names(real)} ran or was cancelled for another reason") unless real.empty?

    mine = group(run.merge("run_attempt" => attempt + 1))
    return leave("its workflow, #{run.fetch('path')}, has a concurrency group this does not know") if mine == :unknown

    newer = mine.nil? ? [] : waiting_behind(run, mine)
    return leave("run #{newer.join(', ')} waits in its concurrency group, which a rerun would replace") unless newer.empty?

    Verdict.new(action: :rerun, reason: "#{names(red)} never got a runner")
  end

  # The IDs of the newer runs waiting in +mine+, the concurrency group
  # +run+'s next attempt joins. GitHub keeps one run waiting in a group,
  # so a rerun would replace any of them; a run waiting in another group
  # it cannot touch.
  private def waiting_behind(run, mine)
    waiting = @github.all("actions/workflows/#{run.fetch('workflow_id')}/runs", "workflow_runs", branch: run.fetch("head_branch"), status: "pending")
    waiting.select { |other| other.fetch("id") > run.fetch("id") && group(other) == mine }.map { |other| other.fetch("id") }
  end

  # The concurrency group a run of trunk is in, as its workflow's
  # concurrency block names it, from what GitHub's API says of the run:
  # +nil+ for none, and :unknown for a workflow this does not follow.
  # The API names no run's group, so this reads it from the run's event,
  # attempt, commit, and message, as the block does. In ci.yml, a push
  # whose message starts as a release or pin commit's, a dispatched run,
  # and every attempt after a run's first have a group named for their
  # commit, and every other run shares trunk's; in fast.yml and
  # fast-macos.yml every run of trunk has its commit's own; ruby-spec.yml
  # has none. A pull request's run, whose head branch can be a fork's
  # trunk, has its pull request's ref in its group, and shares none with
  # a run of trunk. Groups are compared only between runs of one workflow
  # and branch, so the workflow's name and the ref are left out.
  private def group(run)
    return "a pull request's" if run["event"] == "pull_request"

    case run.fetch("path")
    when ".github/workflows/ci.yml"
      own_ci_group?(run) ? run.fetch("head_sha") : BRANCH
    when ".github/workflows/fast.yml", ".github/workflows/fast-macos.yml" then run.fetch("head_sha")
    when ".github/workflows/ruby-spec.yml" then nil
    else :unknown
    end
  end

  # Whether a run of ci.yml on trunk has a group named for its commit.
  private def own_ci_group?(run)
    return true if run["event"] == "workflow_dispatch" || run.fetch("run_attempt") > 1

    run["event"] == "push" && run.dig("head_commit", "message").to_s.start_with?(*OWN_GROUP)
  end

  # A job GitHub cancelled before any runner took it: no runner, no
  # steps, and GitHub's annotation saying so. An annotation's message may
  # be null in GitHub's schema, and then says nothing.
  private def runnerless?(job)
    return false unless job["conclusion"] == "cancelled" && job.fetch("steps").empty? && job["runner_name"].to_s.empty?

    annotations = @github.get("check-runs/#{job.fetch('id')}/annotations", per_page: PER_PAGE, page: 1)
    annotations.any? { |annotation| annotation["message"].to_s.start_with?(NOT_ACQUIRED) }
  end

  private def names(jobs)
    jobs.map { |job| job.fetch("name") }.join(", ")
  end

  private def leave(reason)
    Verdict.new(action: :leave, reason:)
  end
end

if $PROGRAM_NAME == __FILE__
  dry_run = ARGV.delete("--dry-run")
  id, attempt = ARGV
  abort "usage: ruby tasks/runnerless_runs.rb RUN ATTEMPT [--dry-run]" unless id && attempt
  token = ENV["GH_TOKEN"] || ENV.fetch("GITHUB_TOKEN")
  api = ENV.fetch("GITHUB_API_URL", "https://api.github.com")
  runs = RunnerlessRuns.new(repository: ENV.fetch("GITHUB_REPOSITORY"), token:, api:, dry_run: !dry_run.nil?)
  begin
    verdict = runs.call(Integer(id), Integer(attempt))
    done = { rerun: dry_run ? "Would run its failed jobs again" : "Ran its failed jobs again", leave: "Left it as it is" }.fetch(verdict.action)
    puts "Run #{id}, attempt #{attempt}: #{done}: #{verdict.reason}."
  rescue GitHubAPI::Error => e
    abort "#{'::error::' if ENV['GITHUB_ACTIONS']}#{e.message}"
  end
end
