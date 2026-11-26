# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/loopback_server"
require_relative "../tasks/green_walk"
require "json"
require "open3"

# Which commit of trunk a landed change is released at: real git, and
# tasks/ci_runs.rb reading a loopback server that answers as GitHub's
# API does.
class GreenWalkTest < Minitest::Test
  def test_the_change_itself_when_its_own_run_is_green
    with_trunk(%w[success success]) do |shas, walk|
      assert_equal shas[1], walk.first_green(shas[1])
    end
  end

  def test_a_later_commit_when_the_change_has_no_green_run
    with_trunk([nil, "failure", nil, "success", "success"]) do |shas, walk|
      assert_equal shas[3], walk.first_green(shas[1])
    end
  end

  def test_nothing_when_no_commit_from_the_change_on_has_a_green_run
    with_trunk(["success", "failure", nil, "cancelled"]) do |shas, walk|
      assert_nil walk.first_green(shas[1])
    end
  end

  # A side branch's green commit, merged into trunk by a merge with no
  # run, is not a commit trunk was ever at.
  def test_a_commit_off_the_first_parent_line_is_not_walked
    with_trunk([nil, nil, nil], side: "success") do |shas, walk|
      assert_nil walk.first_green(shas[1])
    end
  end

  def test_a_change_not_on_the_branch_is_an_error
    with_trunk(["success"]) do |_, walk|
      assert_raises(GreenWalk::Error) { walk.first_green("f" * 40) }
    end
  end

  # GitHub failing is no commit's answer: the walk stops, and does not
  # take the next commit as having no run.
  def test_an_api_failure_ends_the_walk
    with_trunk(%w[success], routes: false) do |shas, walk|
      assert_raises(CIRuns::Error) { walk.first_green(shas[0]) }
    end
  end

  # +conclusions+ gives each commit of trunk's first-parent line, oldest
  # first, the conclusion of its one run of ci.yml, or none. With +side+,
  # a commit on a side branch with that conclusion is merged into trunk
  # by the last commit of the line.
  private def with_trunk(conclusions, side: nil, routes: true)
    Dir.mktmpdir do |dir|
      shas, off = history(dir, conclusions.size, merge: !side.nil?)
      server = LoopbackServer.new(routes ? routes_for(shas + [off].compact, conclusions + [side].compact) : {})
      runs = CIRuns.new(repository: "setdef/Fledge", token: "secret", api: server.url(""), pause: 0)
      yield shas, GreenWalk.new(runs:, dir:, branch: "trunk")
    ensure
      server&.stop
    end
  end

  private def history(dir, count, merge:)
    author = ["-c", "user.name=t", "-c", "user.email=t@example.com"]
    git(dir, "init", "--quiet", "-b", "trunk")
    shas = Array.new(merge ? count - 1 : count) do |index|
      git(dir, *author, "commit", "--quiet", "--allow-empty", "-m", "commit #{index}")
      git(dir, "rev-parse", "HEAD").strip
    end
    return [shas] unless merge

    git(dir, "checkout", "--quiet", "-b", "side", shas[0])
    git(dir, *author, "commit", "--quiet", "--allow-empty", "-m", "side")
    off = git(dir, "rev-parse", "HEAD").strip
    git(dir, "checkout", "--quiet", "trunk")
    git(dir, *author, "merge", "--quiet", "--no-ff", "-m", "merge", "side")
    [shas + [git(dir, "rev-parse", "HEAD").strip], off]
  end

  private def routes_for(shas, conclusions)
    shas.each_with_index.with_object({}) do |(sha, index), routes|
      conclusion = conclusions[index]
      found = conclusion ? [
{
        id: 100 + index,
        html_url: "https://github.test/runs/#{100 + index}",
        head_sha: sha,
        head_branch: "trunk",
        event: "push",
        status: "completed",
        conclusion:,
        run_attempt: 1,
      },
] : []
      routes["/repos/setdef/Fledge/actions/workflows/ci.yml/runs?head_sha=#{sha}&per_page=50&page=1"] =
        [200, {}, JSON.generate(total_count: found.size, workflow_runs: found)]
      next unless conclusion

      job = { name: "Gate", status: "completed", conclusion: }
      routes["/repos/setdef/Fledge/actions/runs/#{100 + index}/jobs?filter=latest&per_page=50&page=1"] =
        [200, {}, JSON.generate(total_count: 1, jobs: [job])]
    end
  end

  private def git(dir, *)
    out, status = Open3.capture2e("git", *, chdir: dir)
    assert status.success?, out
    out
  end
end
