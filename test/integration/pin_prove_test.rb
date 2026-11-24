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

  private def prove(trunk_run:, branch_run: "completed success")
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
      env = {
        "PATH" => "#{bin}:#{ENV.fetch("PATH")}", "GITHUB_OUTPUT" => File.join(dir, "output"),
        "GITHUB_STEP_SUMMARY" => File.join(dir, "summary"), "GITHUB_SERVER_URL" => "https://github.test",
        "GITHUB_REPOSITORY" => "setdef/Fledge"
      }
      FileUtils.touch([env["GITHUB_OUTPUT"], env["GITHUB_STEP_SUMMARY"]])
      _out, err, status = Open3.capture3(env, "bash", SCRIPT, "report.json", chdir: checkout)
      git(work, "pull", "--quiet", "origin", "trunk")
      {
        status: status.exitstatus, stderr: err, summary: File.read(env["GITHUB_STEP_SUMMARY"]),
        output: File.read(env["GITHUB_OUTPUT"]), trunk_version: File.read(File.join(work, "version")).strip
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
    shim(bin, "gh", <<~SH)
      case "$1 $2" in
        "workflow run") n=$(($(cat #{dir}/runs 2>/dev/null || echo 0) + 1)); echo $n > #{dir}/runs ;;
        "run list") cat #{dir}/runs ;;
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

  private def git(dir, *args)
    out, status = Open3.capture2e("git", *args, chdir: dir)
    assert status.success?, out
    out
  end
end
