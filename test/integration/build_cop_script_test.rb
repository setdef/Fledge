# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "fileutils"
require "open3"
require "tmpdir"

# .github/scripts/build-cop.sh's revert step (doc/contributors/design/
# releases.md, "The build cop"), run as a subprocess in a real clone of
# a real origin, with tasks/build_cop.rb replaced by a file that says
# what to do and gh by one that writes down what it was asked.
class BuildCopScriptTest < Minitest::Test
  SCRIPT = File.expand_path("../../.github/scripts/build-cop.sh", __dir__)

  # gh as the script asks it: every call written down; a dispatch or a
  # rerun refused when the file gh.fail_dispatch or gh.fail_rerun is
  # there; and the runs it lists are those in gh.live (the ID of the
  # first run that is not cancelled) and gh.any (how many runs there are
  # at all), as the script's two queries ask for.
  FAKE_GH = <<~SH
    #!/bin/sh
    echo "$@" >>"DIR/gh.log"
    case "$*" in
    *"workflow run"*) [ -f "DIR/gh.fail_dispatch" ] && exit 1 ;;
    *"run rerun"*) [ -f "DIR/gh.fail_rerun" ] && { echo "run cannot be rerun" >&2; exit 1; } ;;
    *"run list"*)
      case "$*" in
      *length*) cat "DIR/gh.any" 2>/dev/null ;;
      *) cat "DIR/gh.live" 2>/dev/null ;;
      esac
      ;;
    esac
    exit 0
  SH

  WITH_DISPATCH = "name: CI\non:\n  push:\n    branches: [trunk]\n  workflow_dispatch:\n"
  WITHOUT_DISPATCH = "name: CI\non:\n  push:\n    branches: [trunk]\n"

  def setup
    @dir = Dir.mktmpdir("build-cop")
    @origin = File.join(@dir, "origin.git")
    @work = File.join(@dir, "work")
    git(@dir, "init", "--quiet", "--bare", "--initial-branch=trunk", @origin)
    git(@dir, "clone", "--quiet", @origin, @work)
    git(@work, "checkout", "--quiet", "-b", "trunk")
    commit("base", "base.txt" => "base\n")
    FileUtils.mkdir_p(File.join(@work, "tasks"))
    FileUtils.mkdir_p(File.join(@dir, "bin"))
    File.write(File.join(@dir, "bin", "gh"), FAKE_GH.gsub("DIR", @dir), perm: 0o755)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_a_commit_reverted_already_is_left_alone_however_long_trunks_history
    bad = commit("feat: bad", "bad.txt" => "bad\n")
    git(@work, "revert", "--no-edit", bad)
    # More log than a pipe holds, below the revert, so that a reader that
    # stops at the match leaves the log writing into a closed pipe.
    30.times { |index| commit("filler #{index} #{'x' * 4000}", "f#{index}.txt" => "x\n") }
    git(@work, "push", "--quiet", "origin", "trunk")
    before = origin_head

    out, status = cop(bad, "revert", env: { "BUILD_COP_REVERT" => "true" })

    assert_predicate status, :success?, out
    assert_match(/reverted on trunk already/, out)
    assert_equal before, origin_head
    refute File.exist?(File.join(@dir, "gh.log"))
  end

  def test_it_reverts_nothing_until_asked_to
    bad = commit("feat: bad", "bad.txt" => "bad\n")
    git(@work, "push", "--quiet", "origin", "trunk")
    before = origin_head

    out, status = cop(bad, "revert")

    assert_predicate status, :success?, out
    assert_match(/BUILD_COP_REVERT is not true/, out)
    assert_equal before, origin_head
  end

  def test_it_reverts_the_commit_and_starts_a_run_on_trunk_when_asked_to
    bad = commit("feat: bad", "bad.txt" => "bad\n")
    git(@work, "push", "--quiet", "origin", "trunk")

    out, status = cop(bad, "revert", env: { "BUILD_COP_REVERT" => "true" })

    assert_predicate status, :success?, out
    message = git(@dir, "--git-dir", @origin, "log", "-1", "--format=%B", "trunk")

    assert_match(/\Arevert: feat: bad\n/, message)
    assert_includes message, "This reverts commit #{bad}."
    refute_includes git(@dir, "--git-dir", @origin, "ls-tree", "--name-only", "trunk"), "bad.txt"
    assert_includes File.read(File.join(@dir, "gh.log")), "workflow run ci.yml --ref trunk"
  end

  def test_a_release_pin_record_or_revert_is_a_persons_to_revert
    ["chore: release 0.9.0", "chore: pin runtimes", "chore: record 0.9.0 on trunk", "revert: feat: bad"].each_with_index do |subject, index|
      bad = commit(subject, "s#{index}.txt" => "x\n")
      git(@work, "push", "--quiet", "origin", "trunk")
      before = origin_head

      out, status = cop(bad, "revert", env: { "BUILD_COP_REVERT" => "true" })

      assert_predicate status, :success?, out
      assert_match(/a person's to revert/, out, subject)
      assert_equal before, origin_head, subject
    end
  end

  def test_it_bisects_on_a_branch_and_starts_ci_there
    bad = bisect_commit(WITH_DISPATCH)

    out, status = cop_bisecting(bad)

    assert_predicate status, :success?, out
    assert_includes origin_branches, "bisect/#{bad}"
    assert_includes gh_log, "workflow run ci.yml --ref bisect/#{bad}"
  end

  # A commit from before ci.yml could be started by hand cannot be run
  # on a branch: GitHub refuses the dispatch, and the cop's own run
  # would go red every half hour.
  def test_a_commit_whose_ci_cannot_be_started_by_hand_is_left_for_a_person
    bad = bisect_commit(WITHOUT_DISPATCH)

    out, status = cop_bisecting(bad)

    assert_predicate status, :success?, out
    assert_match(/::warning::.*workflow_dispatch/, out)
    refute_includes gh_log, "workflow run"
    assert_empty origin_branches.strip
  end

  # GitHub may take minutes to list a run it was asked to start, and
  # the next call, which finds no run of the commit, says to bisect it
  # again.
  def test_a_run_that_is_not_listed_yet_is_not_started_twice
    bad = bisect_commit(WITH_DISPATCH)
    cop_bisecting(bad)
    File.delete(File.join(@dir, "gh.log"))

    out, status = cop_bisecting(bad)

    assert_predicate status, :success?, out
    refute_includes gh_log, "workflow run"
    assert_match(/not listed/, out)
  end

  def test_a_run_that_was_cancelled_is_started_again
    bad = bisect_commit(WITH_DISPATCH)
    cop_bisecting(bad)
    File.write(File.join(@dir, "gh.any"), "1\n")
    File.delete(File.join(@dir, "gh.log"))

    out, status = cop_bisecting(bad)

    assert_predicate status, :success?, out
    assert_includes gh_log, "workflow run ci.yml --ref bisect/#{bad}"
    assert_includes origin_branches, "bisect/#{bad}"
  end

  # A branch with no run to come would make every later call wait.
  def test_a_dispatch_that_fails_leaves_no_branch_behind
    bad = bisect_commit(WITH_DISPATCH)
    File.write(File.join(@dir, "gh.fail_dispatch"), "")

    _out, status = cop_bisecting(bad)

    refute_predicate status, :success?
    assert_empty origin_branches.strip
  end

  # GitHub refuses to run again the jobs of a run that has no failed
  # job, or is running again already: that is a warning, not a red run
  # of the cop.
  def test_a_rerun_that_github_refuses_is_a_warning
    File.write(File.join(@dir, "gh.fail_rerun"), "")

    run = commit("feat: x", "x.txt" => "x\n")
    git(@work, "push", "--quiet", "origin", "trunk")

    out, status = cop(run, "rerun")

    assert_predicate status, :success?, out
    assert_match(/::warning::.*run 1/, out)
  end

  private def bisect_commit(workflow)
    bad = commit("feat: to bisect", ".github/workflows/ci.yml" => workflow)
    git(@work, "push", "--quiet", "origin", "trunk")
    bad
  end

  private def gh_log
    File.exist?(File.join(@dir, "gh.log")) ? File.read(File.join(@dir, "gh.log")) : ""
  end

  private def origin_branches
    git(@dir, "--git-dir", @origin, "branch", "--list", "bisect/*")
  end

  private def cop_bisecting(commit)
    cop(commit, "bisect", env: { "BUILD_COP_LIST_TRIES" => "1", "BUILD_COP_LIST_PAUSE" => "0" })
  end

  private def cop(commit, action, env: {})
    File.write(File.join(@work, "tasks", "build_cop.rb"),
      "puts \"action=#{action}\", \"commit=#{commit}\", \"run=1\", \"reason=a test\"\n")
    env = {
"PATH" => "#{File.join(@dir, 'bin')}:#{ENV.fetch('PATH')}",
"GIT_CONFIG_GLOBAL" => "/dev/null",
"GIT_CONFIG_SYSTEM" => "/dev/null",
"GIT_AUTHOR_NAME" => "t",
"GIT_AUTHOR_EMAIL" => "t@example.com",
"GIT_COMMITTER_NAME" => "t",
"GIT_COMMITTER_EMAIL" => "t@example.com",
}.merge(env)
    Open3.capture2e(env, "bash", SCRIPT, chdir: @work)
  end

  private def commit(message, files)
    files.each do |name, text|
      FileUtils.mkdir_p(File.dirname(File.join(@work, name)))
      File.write(File.join(@work, name), text)
    end
    git(@work, "add", "--all")
    git(@work, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m", message)
    git(@work, "rev-parse", "HEAD").strip
  end

  private def origin_head
    git(@dir, "--git-dir", @origin, "rev-parse", "trunk").strip
  end

  private def git(dir, *args)
    out, status = Open3.capture2e({ "GIT_CONFIG_GLOBAL" => "/dev/null" }, "git", *args, chdir: dir)
    raise "git #{args.join(' ')}: #{out}" unless status.success?

    out
  end
end
