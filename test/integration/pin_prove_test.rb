# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"

# What .github/scripts/pin-prove.sh reports once a proven move is on
# trunk (doc/contributors/design/runtimes.md, "The proof"), run as the
# workflow runs it, with real git and a real bare origin, and only the
# two things that need GitHub or the pins' upstreams standing in: gh,
# which answers each run of ci.yml with the conclusion the test gives
# it, and the move itself, which changes one file.
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
  # The move is judged by the run the dispatch started, and the summary
  # says whose head it is.
  def test_a_move_is_judged_by_the_run_its_dispatch_started_whatever_its_head
    result = prove(trunk_run: "completed success", trunk_list: :later)

    assert_equal 0, result[:status], result[:stderr]
    assert_includes result[:summary], "actions/runs/2"
    assert_includes result[:summary], "#{'f' * 40}, a later commit than the one landed"
    assert_includes result[:summary], "not released"
    refute_match(/^landed=/, result[:output], "a run of another commit is not the move's run")
    assert_equal "changed", result[:trunk_version]
  end

  def test_a_run_of_the_landed_commit_does_not_say_it_is_a_later_commit
    result = prove(trunk_run: "completed success")

    refute_includes result[:summary], "a later commit"
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

  # The runs gh lists for the dispatch whose number is the key, as JSON,
  # where HERE stands for the commit checked out when gh is asked.
  RUN_LISTS = {
    own: '[{"databaseId":%d,"headSha":"HERE","createdAt":"2099-01-01T00:00:00Z"}]',
    later: "[{\"databaseId\":%d,\"headSha\":\"#{'f' * 40}\",\"createdAt\":\"2099-01-01T00:00:00Z\"}]",
    stale: '[{"databaseId":%d,"headSha":"HERE","createdAt":"2000-01-01T00:00:00Z"}]',
    none: "[]",
  }.freeze

  private def prove(trunk_run:, branch_run: "completed success", trunk_list: :own, branch_list: :own)
    Dir.mktmpdir do |dir|
      work = File.join(dir, "work")
      checkout = File.join(dir, "checkout")
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      git(dir, "init", "--quiet", "--bare", "-b", "trunk", File.join(dir, "origin.git"))
      git(dir, "clone", "--quiet", File.join(dir, "origin.git"), work)
      File.write(File.join(work, ".gitignore"), "tmp/\n")
      commit(work, "version", "base")
      git(work, "push", "--quiet", "origin", "HEAD:trunk")
      git(dir, "clone", "--quiet", File.join(dir, "origin.git"), checkout)
      commit(work, "other", "landed meanwhile")
      git(work, "push", "--quiet", "origin", "HEAD:trunk")
      write_shims(bin, dir, branch_run, trunk_run)
      { 1 => branch_list, 2 => trunk_list }.each { |number, kind| File.write(File.join(dir, "list-#{number}.json"), format(RUN_LISTS.fetch(kind), number)) }
      env = {
        "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
        "GITHUB_OUTPUT" => File.join(dir, "output"),
        "GITHUB_STEP_SUMMARY" => File.join(dir, "summary"),
        "GITHUB_SERVER_URL" => "https://github.test",
        "GITHUB_REPOSITORY" => "setdef/Fledge",
      }
      FileUtils.touch([env["GITHUB_OUTPUT"], env["GITHUB_STEP_SUMMARY"]])
      out, err, status = Open3.capture3(env, "bash", SCRIPT, "report.json", chdir: checkout)
      git(work, "pull", "--quiet", "origin", "trunk")
      {
        status: status.exitstatus,
        stderr: err,
        stdout: out,
        summary: File.read(env["GITHUB_STEP_SUMMARY"]),
        output: File.read(env["GITHUB_OUTPUT"]),
        trunk_version: File.read(File.join(work, "version")).strip,
      }
    end
  end

  private def write_shims(bin, dir, branch_run, trunk_run)
    shim(bin, "ruby", <<~SH)
      echo changed > version
      printf 'chore: move zlib\\n' > "$4"
      echo "moved zlib"
    SH
    shim(bin, "bundle", ": # rake licensing")
    shim(bin, "sleep", ":")
    shim(bin, "gh", <<~SH)
      case "$1 $2" in
        "workflow run") n=$(($(cat #{dir}/runs 2>/dev/null || echo 0) + 1)); echo $n > #{dir}/runs ;;
        "run list")
          expr=.; commit=
          while [ $# -gt 0 ]; do
            case "$1" in --jq) expr=$2 ;; --commit) commit=$2 ;; esac
            shift
          done
          sed "s/HERE/$(git rev-parse HEAD)/" #{dir}/list-$(cat #{dir}/runs).json |
            jq --arg c "$commit" 'map(select($c == "" or .headSha == $c))' | jq -r "$expr" ;;
        "run view")
          case "$*" in
            *status,conclusion*) if [ "$(cat #{dir}/runs)" = 1 ]; then echo "#{branch_run}"; else echo "#{trunk_run}"; fi ;;
          esac ;;
      esac
    SH
  end

  private def shim(bin, name, body)
    path = File.join(bin, name)
    File.write(path, "#!/usr/bin/env bash\n#{body}")
    File.chmod(0o755, path)
  end

  private def commit(dir, file, text)
    File.write(File.join(dir, file), "#{text}\n")
    git(dir, "add", "--all")
    git(dir, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m", text)
  end

  private def git(dir, *)
    out, status = Open3.capture2e("git", *, chdir: dir)
    assert status.success?, out
    out
  end
end
