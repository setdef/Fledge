# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/loopback_server"
require "json"
require "open3"
require "yaml"

# Which commit pin-watch.yml's Pick job offers to the release when the
# Alone jobs landed the moves: the step's own script, run as the workflow runs
# it, with real git, and the real tasks/ci_runs.rb and tasks/green_walk.rb
# reading a loopback server that answers as GitHub's API does. Only gh
# stands in, for the one lookup of when the run started.
class PinPickTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  WORKFLOW = YAML.load_file(File.join(ROOT, ".github/workflows/pin-watch.yml"), aliases: true)

  # A move that the Alone path rebased has no green run of its own, and
  # trunk's head after it does: the head holds the move.
  def test_a_move_whose_later_head_is_green_is_released_at_that_head
    result = pick({ 2 => { id: 20, conclusion: "success" } })

    assert_equal 0, result[:status], result[:stderr] + result[:stdout]
    assert_equal result[:shas][2], result[:commit]
  end

  # The first commit from the move on that has a green run is taken, not
  # the newest.
  def test_the_first_green_commit_from_the_move_on_is_released
    result = pick({ 1 => { id: 10, conclusion: "success" }, 2 => { id: 20, conclusion: "success" } })

    assert_equal result[:shas][1], result[:commit], result[:stderr] + result[:stdout]
  end

  # A green run of a commit before the move holds nothing of it.
  def test_a_green_commit_before_the_move_is_not_released
    result = pick({ 0 => { id: 5, conclusion: "success" } })

    assert_equal 0, result[:status], result[:stderr] + result[:stdout]
    assert_empty result[:commit].to_s
    assert_includes result[:stdout], "::warning::"
  end

  def test_a_move_with_no_green_run_at_or_after_it_releases_nothing
    result = pick({ 1 => { id: 10, conclusion: "failure" }, 2 => { id: 20, conclusion: "cancelled" } })

    assert_equal 0, result[:status], result[:stderr] + result[:stdout]
    assert_empty result[:commit].to_s
    assert_includes result[:stdout], "::warning::"
    assert_includes result[:stdout], "nothing to release"
  end

  # Move's release output is used as it is: its job already judged it.
  def test_the_release_the_move_job_offers_is_taken_as_it_is
    result = pick({}, release: :move)

    assert_equal result[:shas][1], result[:commit], result[:stderr] + result[:stdout]
  end

  private def pick_script
    WORKFLOW.dig("jobs", "pick", "steps").find { |each| each["id"] == "pick" }.fetch("run")
  end

  # +runs+ maps a commit's place on trunk (0 the base, 1 the move, 2 a
  # later push) to the one run it has.
  private def pick(runs, release: nil)
    Dir.mktmpdir do |dir|
      checkout = File.join(dir, "checkout")
      shas = trunk_of(checkout)
      server = LoopbackServer.new(routes_for(shas, runs))
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p([bin, File.join(dir, "tmp")])
      FileUtils.ln_s(File.join(ROOT, "tasks"), File.join(checkout, "tasks"))
      write_gh(bin)
      output = File.join(dir, "output")
      FileUtils.touch(output)
      env = {
        "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
        "RELEASE" => (release == :move) ? shas[1] : "",
        "GITHUB_RUN_ID" => "1",
        "GH_TOKEN" => "secret",
        "GITHUB_REPOSITORY" => "setdef/Fledge",
        "GITHUB_API_URL" => server.url(""),
        "GITHUB_ACTIONS" => "true",
        "GITHUB_OUTPUT" => output,
        "RUNNER_TEMP" => File.join(dir, "tmp"),
      }
      script = File.join(dir, "pick.sh")
      File.write(script, pick_script)
      out, err, status = Open3.capture3(env, "bash", "-e", script, chdir: checkout)
      { status: status.exitstatus, stdout: out, stderr: err, shas:, commit: File.read(output)[/^commit=(\h*)$/, 1] }
    ensure
      server&.stop
    end
  end

  # The base, a move of the bot's, and a later push.
  private def trunk_of(checkout)
    FileUtils.mkdir_p(checkout)
    git(checkout, "init", "--quiet", "-b", "trunk")
    [["commit 0", "t"], ["chore: move zlib", "github-actions[bot]"], ["commit 2", "t"]].each_with_index.map do |(subject, author), index|
      File.write(File.join(checkout, "file"), "#{index}\n")
      File.write(File.join(checkout, "CHANGELOG.md"), "## [Unreleased]\n\n- Something a person can observe.\n\n## [0.1.0]\n")
      git(checkout, "add", "--all")
      git(checkout, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "--author", "#{author} <t@example.com>", "-m", subject)
      git(checkout, "rev-parse", "HEAD").strip
    end
  end

  private def routes_for(shas, runs)
    shas.each_with_index.with_object({}) do |(sha, index), routes|
      run = runs[index]
      found = run ? [
{
        id: run[:id],
        html_url: "https://github.test/runs/#{run[:id]}",
        head_sha: sha,
        head_branch: "trunk",
        event: "push",
        status: "completed",
        conclusion: run[:conclusion],
        run_attempt: 1,
      },
] : []
      routes["/repos/setdef/Fledge/actions/workflows/ci.yml/runs?head_sha=#{sha}&per_page=50&page=1"] =
        [200, {}, JSON.generate(total_count: found.size, workflow_runs: found)]
      next unless run

      job = { name: "Gate", status: "completed", conclusion: run[:conclusion] }
      routes["/repos/setdef/Fledge/actions/runs/#{run[:id]}/jobs?filter=latest&per_page=50&page=1"] =
        [200, {}, JSON.generate(total_count: 1, jobs: [job])]
    end
  end

  # gh run view 1 --json createdAt --jq .createdAt: when the run began.
  private def write_gh(bin)
    File.write(File.join(bin, "gh"), "#!/usr/bin/env bash\necho 2000-01-01T00:00:00Z\n")
    File.chmod(0o755, File.join(bin, "gh"))
  end

  private def git(dir, *)
    out, status = Open3.capture2e("git", *, chdir: dir)
    assert status.success?, out
    out
  end
end
