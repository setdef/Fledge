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
      File.write(File.join(dir, "ancestor-sha"), git(work, "rev-parse", "HEAD"))
      write_shims(bin, dir, work, branch_run, trunk_run)
      { 1 => branch_list, 2 => trunk_list }.each { |number, kind| File.write(File.join(dir, "list-#{number}.json"), RUN_LISTS.fetch(kind).gsub("%d", number.to_s)) }
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
        later: File.exist?(File.join(dir, "later-sha")) ? File.read(File.join(dir, "later-sha")).strip : nil,
        status: status.exitstatus,
        stderr: err,
        stdout: out,
        summary: File.read(env["GITHUB_STEP_SUMMARY"]),
        output: File.read(env["GITHUB_OUTPUT"]),
        trunk_version: File.read(File.join(work, "version")).strip,
      }
    end
  end

  private def write_shims(bin, dir, work, branch_run, trunk_run)
    shim(bin, "ruby", <<~SH)
      echo changed > version
      printf 'chore: move zlib\\n' > "$4"
      echo "moved zlib"
    SH
    shim(bin, "bundle", ": # rake licensing")
    shim(bin, "sleep", ":")
    shim(bin, "gh", <<~SH)
      case "$1 $2" in
        "workflow run")
          n=$(($(cat #{dir}/runs 2>/dev/null || echo 0) + 1)); echo $n > #{dir}/runs
          # A push that lands between the move's and the dispatch, which
          # the run then takes as its head.
          if [ $n = 2 ] && grep -q LATER #{dir}/list-2.json; then
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
          sed -e "s/HERE/$(git rev-parse HEAD)/" -e "s/LATER/$(cat #{dir}/later-sha 2>/dev/null)/" -e "s/ANCESTOR/$(cat #{dir}/ancestor-sha)/" #{dir}/list-$(cat #{dir}/runs).json |
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
