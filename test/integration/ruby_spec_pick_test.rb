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

# Which run's runtimes ruby-spec.yml takes when it runs by itself, at
# night or by hand:
# the step's own script, run as the workflow runs it, with real git and
# the real tasks/ci_runs.rb reading a loopback server that answers as
# GitHub's API does. Only gh stands in, for the one artifact lookup that
# reads GitHub's other endpoint.
class RubySpecPickTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  WORKFLOW = YAML.load_file(File.join(ROOT, ".github/workflows/ruby-spec.yml"), aliases: true)

  # A pin move that landed as proven has only the proof's run, a
  # dispatch on pin-move, and it is trunk's newest commit.
  def test_the_newest_commit_whose_only_green_run_is_a_dispatch_on_another_branch_is_picked
    result = pick(
      2 => { id: 20, event: "push", branch: "trunk", runtimes: true },
      3 => { id: 30, event: "workflow_dispatch", branch: "pin-move", runtimes: true },
    )

    assert_equal 0, result[:status], result[:stderr]
    assert_equal "30", result[:run]
  end

  # A commit that has no green run is passed over, and so is one whose
  # green run holds no runtimes, as a pin commit's short run does not.
  def test_commits_without_a_green_run_with_runtimes_are_passed_over
    result = pick(
      1 => { id: 10, event: "push", branch: "trunk", runtimes: true },
      2 => { id: 20, event: "push", branch: "trunk", runtimes: false },
      3 => { id: 30, event: "push", branch: "trunk", runtimes: true, conclusion: "failure" },
    )

    assert_equal 0, result[:status], result[:stderr]
    assert_equal "10", result[:run]
  end

  # A pull request's run checks out a merge of its commit, not the
  # commit, so it is no commit's run (tasks/ci_runs.rb).
  def test_a_run_of_a_pull_request_is_not_a_commits_run
    result = pick(3 => { id: 30, event: "pull_request", branch: "feature", runtimes: true })

    assert_equal 1, result[:status]
    assert_empty result[:run].to_s
    assert_includes result[:stdout], "::error::"
  end

  private def plan_script
    step = WORKFLOW.dig("jobs", "plan", "steps").find { |each| each["id"] == "plan" }
    step.fetch("run")
  end

  # +runs+ maps a commit's place on trunk (0 the oldest, 3 the newest)
  # to the one run it has, and the run's number.
  private def pick(runs)
    Dir.mktmpdir do |dir|
      checkout = File.join(dir, "checkout")
      shas = trunk_of(checkout, 4)
      server = LoopbackServer.new(routes_for(shas, runs))
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      FileUtils.ln_s(File.join(ROOT, "tasks"), File.join(checkout, "tasks"))
      write_gh(bin, runs)
      output = File.join(dir, "output")
      env = {
        "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
        "BY_ITSELF" => "true",
        "FULL" => "false",
        "GH_TOKEN" => "secret",
        "REPOSITORY" => "setdef/Fledge",
        "GITHUB_REPOSITORY" => "setdef/Fledge",
        "GITHUB_API_URL" => server.url(""),
        "GITHUB_ACTIONS" => "true",
        "GITHUB_OUTPUT" => output,
        "GITHUB_SERVER_URL" => "https://github.test",
      }
      FileUtils.touch(output)
      script = File.join(dir, "plan.sh")
      File.write(script, plan_script)
      out, err, status = Open3.capture3(env, "bash", "-e", script, chdir: checkout)
      { status: status.exitstatus, stdout: out, stderr: err, run: File.read(output)[/^run=(\d*)$/, 1] }
    ensure
      server&.stop
    end
  end

  private def trunk_of(checkout, count)
    FileUtils.mkdir_p(checkout)
    git(checkout, "init", "--quiet", "-b", "trunk")
    Array.new(count) do |index|
      File.write(File.join(checkout, "file"), "#{index}\n")
      git(checkout, "add", "--all")
      git(checkout, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m", "commit #{index}")
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
head_branch: run[:branch],
event: run[:event],
status: "completed",
conclusion: run[:conclusion] || "success",
run_attempt: 1,
},
] : []
      routes["/repos/setdef/Fledge/actions/workflows/ci.yml/runs?head_sha=#{sha}&per_page=50&page=1"] =
        [200, {}, JSON.generate(total_count: found.size, workflow_runs: found)]
      next unless run

      job = { name: "Gate", status: "completed", conclusion: run[:conclusion] || "success" }
      routes["/repos/setdef/Fledge/actions/runs/#{run[:id]}/jobs?filter=latest&per_page=50&page=1"] =
        [200, {}, JSON.generate(total_count: 1, jobs: [job])]
    end
  end

  # gh api .../runs/ID/artifacts answers 1 for a run whose runtime is
  # still held, and 0 for one whose is not.
  private def write_gh(bin, runs)
    held = runs.values.select { |run| run[:runtimes] }.map { |run| run[:id] }
    File.write(File.join(bin, "gh"), <<~SH)
      #!/usr/bin/env bash
      case " #{held.join(' ')} " in
        *" $(basename "$(dirname "$2")") "*) echo 1 ;;
        *) echo 0 ;;
      esac
    SH
    File.chmod(0o755, File.join(bin, "gh"))
  end

  private def git(dir, *)
    out, status = Open3.capture2e("git", *, chdir: dir)
    assert status.success?, out
    out
  end
end
