# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require_relative "ci_runs"

# Finds the commit to release for a change that landed on trunk: the
# first commit, the change itself or a later one on trunk's first-parent
# line, whose own run of ci.yml passed every job, as tasks/ci_runs.rb
# counts runs (doc/contributors/design/runtimes.md, "The proof").
#
# A change that was rebased onto trunk when it landed has no green run
# of its own when a push followed it, since a run of ci.yml covers every
# commit pushed since the run before it and only its head has a run
# (doc/contributors/design/releases.md, "Runs, batches, and the release
# commit"). A later commit holds the change and has such a run; the
# first of them is the commit that holds the change and was judged.
#
#   ruby tasks/green_walk.rb COMMIT [BRANCH]
#
# prints the commit, or fails saying that no commit from COMMIT to the
# head of BRANCH (trunk by default) has a green run. It reads what
# tasks/ci_runs.rb reads, and runs git in the current folder.
class GreenWalk
  # The change is not on the branch's first-parent line.
  class Error < StandardError; end

  # +runs+ is the CIRuns that says which commit has a green run; +dir+ is
  # the checkout whose +branch+ is walked.
  def initialize(runs:, dir: Dir.pwd, branch: "trunk")
    @runs = runs
    @dir = dir
    @branch = branch
  end

  # The first commit from +change+ to the head of the branch, on the
  # branch's first-parent line, with a green run, or nil when none has.
  # A commit with no green run is passed over; GitHub's failing to answer
  # raises CIRuns::Error, since that says nothing of the commit.
  def first_green(change)
    line = git("rev-list", "--first-parent", "--reverse", @branch).split
    start = line.index(change) or raise Error, "#{change} is not on the first-parent line of #{@branch}"
    line.drop(start).find do |commit|
      @runs.green(commit)
      true
    rescue CIRuns::NotGreen
      false
    end
  end

  private def git(*args)
    out, err, status = Open3.capture3("git", *args, chdir: @dir)
    raise Error, "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end
end

if $PROGRAM_NAME == __FILE__
  change, branch = ARGV.shift(2)
  abort "usage: ruby tasks/green_walk.rb COMMIT [BRANCH]" unless change
  token = ENV["GH_TOKEN"] || ENV.fetch("GITHUB_TOKEN")
  runs = CIRuns.new(repository: ENV.fetch("GITHUB_REPOSITORY"), token:, api: ENV.fetch("GITHUB_API_URL", "https://api.github.com"))
  begin
    found = GreenWalk.new(runs:, branch: branch || "trunk").first_green(change)
    abort "no commit from #{change} to the head of #{branch || 'trunk'} has a green run of #{CIRuns::WORKFLOW}" unless found
    puts found
  rescue GreenWalk::Error, CIRuns::Error => e
    abort e.message
  end
end
