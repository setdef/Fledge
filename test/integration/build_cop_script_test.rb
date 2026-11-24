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
    File.write(File.join(@dir, "bin", "gh"), "#!/bin/sh\necho \"$@\" >>\"#{@dir}/gh.log\"\n", perm: 0o755)
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

  private def cop(commit, action, env: {})
    File.write(File.join(@work, "tasks", "build_cop.rb"),
               "puts \"action=#{action}\", \"commit=#{commit}\", \"run=1\", \"reason=a test\"\n")
    env = { "PATH" => "#{File.join(@dir, 'bin')}:#{ENV.fetch('PATH')}", "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null",
            "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@example.com", "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@example.com" }.merge(env)
    Open3.capture2e(env, "bash", SCRIPT, chdir: @work)
  end

  private def commit(message, files)
    files.each { |name, text| File.write(File.join(@work, name), text) }
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
