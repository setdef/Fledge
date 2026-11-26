# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "github_api"

# Finds the commit that turned trunk's full run red, one step at a time,
# from GitHub's API alone.
#
# A full run of ci.yml on trunk covers a batch: every commit pushed since
# the run before it started (doc/contributors/design/releases.md, "Runs,
# batches, and the release commit"). When a batch goes red after a green
# one, any of its commits may be the one at fault. This class bisects
# the batch with full runs of single commits, started on branches
# <tt>bisect/SHA</tt>, judges each by the jobs that failed in the red
# run, has the run of the first bad commit run its failed jobs again so
# that a flaky job blames nobody, has that commit's parent run them on a
# branch of its own so that a failure from outside the batch blames
# nobody either, and then names that commit to revert (releases.md,
# "The build cop").
#
# It keeps no state: each call reads the runs as they are and says what
# to do next, so .github/workflows/build-cop.yml can call it whenever a
# run ends and on a schedule, and a call that finds the work in progress
# says to wait.
#
#   ruby tasks/build_cop.rb COMMITS
#
# reads trunk's commits, newest first, one per line, from the file
# COMMITS (git rev-list --first-parent), and prints what to do as lines
# +action=+, +commit=+, +run=+, and +reason=+, for GITHUB_OUTPUT. It reads
# GITHUB_REPOSITORY, GITHUB_API_URL, and GH_TOKEN or GITHUB_TOKEN.
class BuildCop
  # What to do next: +action+ is :none, :wait, :bisect, :rerun, :revert,
  # or :stuck; +commit+ is the commit to bisect or revert, +run+ the run
  # to run again, and +reason+ says why, for a person.
  class Step < Data.define(:action, :commit, :run, :reason)
    def self.of(action, reason, commit: nil, run: nil)
      new(action:, commit:, run:, reason:)
    end

    # The lines GITHUB_OUTPUT takes.
    def to_output
      "action=#{action}\ncommit=#{commit}\nrun=#{run}\nreason=#{reason}\n"
    end
  end

  # The workflow bisected, and the branch whose runs are trunk's.
  WORKFLOW = "ci.yml"
  TRUNK = "trunk"

  # The branch a commit's bisecting run is started on.
  BISECT = "bisect/"

  # The events whose runs check out their commit itself
  # (tasks/ci_runs.rb).
  EVENTS = %w[push workflow_dispatch].freeze

  # How far back runs are read: a red batch older than this is a
  # person's.
  DAYS = 3

  # +now+ is the time runs are read back from, by DAYS.
  def initialize(repository:, token:, api: "https://api.github.com", pause: 5, now: Time.now)
    @github = GitHubAPI.new(repository:, token:, api:, pause:)
    @since = (now - (DAYS * 86_400)).utc.strftime("%Y-%m-%d")
    @jobs = {}
  end

  # The next Step for trunk's +commits+, newest first.
  def call(commits)
    runs = @github.all("actions/workflows/#{WORKFLOW}/runs", "workflow_runs", created: ">=#{@since}", exclude_pull_requests: true)
    @runs = runs.select { |run| EVENTS.include?(run.fetch("event")) }.group_by { |run| run.fetch("head_sha") }
    step(commits)
  end

  private def step(commits)
    good = commits.index { |commit| finished_runs(commit).any? { |run| green?(run) } }
    return Step.of(:none, "no commit of the last #{DAYS} days has a green run") unless good

    batch = commits.first(good).reverse
    bad = batch.find { |commit| trunk_runs(commit).any? { |run| run["conclusion"] == "failure" } }
    return Step.of(:none, "no run on #{TRUNK} since #{commits[good]}'s green one is red") unless bad

    red = trunk_runs(bad).find { |run| run["conclusion"] == "failure" }
    failed = jobs(red).select { |job| job["conclusion"] == "failure" }.map { |job| job.fetch("name") }
    return Step.of(:none, "run #{red.fetch('id')} has no job that failed, only ones cancelled or no runner took") if failed.empty?

    narrow([commits[good]] + batch.first(batch.index(bad) + 1), failed)
  end

  # Bisects +commits+, oldest first, the first green and the last red,
  # by whether each commit's newest run failed a job of +failed+.
  private def narrow(commits, failed)
    verdicts = [[:good, nil]] + commits.drop(1).map { |commit| verdict(commit, failed) }
    high = verdicts.index { |each| each.first == :bad }
    return Step.of(:wait, "the run of #{commits.last} is running again") unless high

    low = (0...high).select { |index| verdicts[index].first == :good }.max
    return blame(commits[high], verdicts[high].last, failed, commits[low]) if high - low == 1

    between = ((low + 1)...high)
    return Step.of(:wait, "a run of #{commits[between.find { |index| verdicts[index].first == :pending }]} has not finished") if between.any? { |index| verdicts[index].first == :pending }

    middle = (low + high) / 2
    return untold(commits[middle], verdicts[middle].last, failed) if verdicts[middle].first == :unknown

    Step.of(:bisect, "#{commits[low]} passed #{failed.join(', ')} and #{commits[high]} failed; #{high - low - 1} commits between", commit: commits[middle])
  end

  # The commit after the last green one failed: a job of +failed+ that
  # fails again on a second attempt blames it, once +parent+ has passed
  # them in a run of its own.
  private def blame(commit, run, failed, parent)
    again = jobs(run).any? { |job| failed.include?(job.fetch("name")) && job["conclusion"] == "failure" && job.fetch("run_attempt") > 1 }
    return vouch(commit, run, failed, parent) if again

    Step.of(:rerun, "run #{run.fetch('id')} of #{commit} failed #{failed.join(', ')}, its parent passed, and a second attempt tells a flake apart", commit:, run: run.fetch("id"))
  end

  # A failure that outlasts a rerun, as a rate limit of a mirror may,
  # fails every run alike, and the batch's oldest commit would take the
  # blame while its parent, whose only green run is older than the
  # failure, was never run again. So the parent's own run, on a branch
  # of the cop's, after trunk went red, has to pass the jobs of +failed+;
  # if it fails them, the cause is outside the batch and nothing is
  # reverted.
  private def vouch(commit, run, failed, parent)
    names = failed.join(", ")
    proof, parent_run = verdict(parent, failed, only: BISECT)
    case proof
    when :none
      Step.of(:bisect, "run #{run.fetch('id')} of #{commit} failed #{names} again, and its parent #{parent} has had no run since trunk went red; it is run before #{commit} is blamed", commit: parent)
    when :pending
      Step.of(:wait, "the run of #{parent}, the parent of #{commit}, has not finished")
    when :good
      Step.of(:revert, "run #{run.fetch('id')} of #{commit} failed #{names} again on attempt #{run.fetch('run_attempt')}, and run #{parent_run.fetch('id')} of its parent #{parent} passed them", commit:, run: run.fetch("id"))
    when :bad
      Step.of(:stuck, "the cause is outside the batch: run #{parent_run.fetch('id')} of #{parent}, the parent of #{commit}, failed #{names} too (#{parent_run['html_url'] || parent_run.fetch('id')})")
    else
      untold(parent, parent_run, failed)
    end
  end

  # The run of +commit+ finished without passing or failing a job of
  # +failed+, as when no runner took one or a job it needs failed: its
  # failed jobs are run again once, and then it is a person's. A run
  # that finished green has no failed job, and the API refuses to run
  # again what did not fail.
  private def untold(commit, run, failed)
    told = "run #{run.fetch('id')} of #{commit} finished without passing or failing #{failed.join(', ')}"
    return Step.of(:stuck, "#{told}, and is green, so it has no failed job to run again") if run["conclusion"] == "success"
    return Step.of(:rerun, "#{told}; its failed jobs run again", commit:, run: run.fetch("id")) if run.fetch("run_attempt") == 1

    Step.of(:stuck, "#{told}, on attempt #{run.fetch('run_attempt')}")
  end

  # :good, :bad, :pending, :unknown, or :none, with the run, for
  # +commit+'s newest run, by the jobs named +failed+. With +only+, the
  # runs counted are those on branches that start with it.
  private def verdict(commit, failed, only: nil)
    runs = @runs.fetch(commit, []).reject { |each| each["conclusion"] == "cancelled" }
    runs = runs.select { |each| each.fetch("head_branch").start_with?(only) } if only
    run = runs.max_by { |each| each.fetch("id") }
    return [:none, nil] unless run
    return [:pending, run] unless run.fetch("status") == "completed"

    mine = jobs(run).select { |job| failed.include?(job.fetch("name")) }
    return [:bad, run] if mine.any? { |job| job["conclusion"] == "failure" }
    return [:good, run] if mine.size == failed.size && mine.all? { |job| job["conclusion"] == "success" }

    [:unknown, run]
  end

  # Whether +run+ passed every job it has. A pin commit's short run
  # passes the gate and skips the rest (releases.md, "A pin commit's
  # short CI"), and says nothing of what a full run covers.
  private def green?(run)
    return false unless run["conclusion"] == "success"

    all = jobs(run)
    all.any? && all.all? { |job| job["conclusion"] == "success" }
  end

  # The runs of +commit+ on any branch that have finished, newest
  # first. A run on another branch checks out the same commit, with its
  # files and its ci.yml, so one that passed makes the commit green: a
  # pin move that landed as proven has only the dispatched run of its
  # proof, since a push made with a workflow's token starts no run on
  # trunk (releases.md, "Which runs are a commit's").
  private def finished_runs(commit)
    @runs.fetch(commit, []).select { |run| run.fetch("status") == "completed" }.sort_by { |run| -run.fetch("id") }
  end

  # The finished runs of +commit+ on trunk. Only these make a commit red:
  # trunk's red is what the cop bisects, and a run on another branch
  # says nothing of the batch that run on trunk covered.
  private def trunk_runs(commit)
    finished_runs(commit).select { |run| run.fetch("head_branch") == TRUNK }
  end

  private def jobs(run)
    @jobs[[run.fetch("id"), run.fetch("run_attempt")]] ||= @github.all("actions/runs/#{run.fetch('id')}/jobs", "jobs", filter: "latest")
  end
end

if $PROGRAM_NAME == __FILE__
  path = ARGV.fetch(0) { abort "usage: ruby tasks/build_cop.rb COMMITS" }
  token = ENV["GH_TOKEN"] || ENV.fetch("GITHUB_TOKEN")
  cop = BuildCop.new(repository: ENV.fetch("GITHUB_REPOSITORY"), token:, api: ENV.fetch("GITHUB_API_URL", "https://api.github.com"))
  begin
    print cop.call(File.readlines(path, chomp: true).reject(&:empty?)).to_output
  rescue GitHubAPI::Error => e
    abort "#{'::error::' if ENV['GITHUB_ACTIONS']}#{e.message}"
  end
end
