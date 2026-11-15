# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../../tasks/fast_check"
require "open3"

# What the fast check before a push (bin/check, tasks/fast_check.rb)
# reads from a real repository that git makes: the commits about to be
# pushed, whether git parses each one's Provenance trailer, and the
# files they and the working tree change.
class FastCheckTest < Minitest::Test
  FOOTER = "Co-Authored-By: Claude <noreply@anthropic.com>"

  def setup
    @root = Dir.mktmpdir
    git("init", "--quiet", "--initial-branch=trunk")
    write("README.md" => "hello\n", "sig/old.rbs" => "class Old\nend\n", "gone.rb" => "1\n")
    @base = commit("docs: start\n\nProvenance: requested\n#{FOOTER}\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def git(*)
    out, err, status = Open3.capture3("git", "-c", "user.name=Fledge", "-c", "user.email=fledge@example.com", *, chdir: @root)
    assert_predicate status, :success?, err
    out
  end

  def write(files)
    files.each do |path, content|
      FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
      File.write(File.join(@root, path), content)
    end
  end

  def commit(message)
    git("add", "--all")
    git("commit", "--quiet", "--allow-empty", "-m", message)
    git("rev-parse", "HEAD").strip
  end

  # Two commits on origin/trunk's tip, one whose trailer git parses and
  # one with a blank line between it and the footer, which git parses as
  # no trailer of its own.
  def two_commits
    git("update-ref", "refs/remotes/origin/trunk", @base)
    write("lib/new.rb" => "1\n")
    File.delete(File.join(@root, "gone.rb"))
    marked = commit("feat(lib): add new\n\nWhy.\n\nProvenance: requested\n#{FOOTER}\n")
    write("README.md" => "hello again\n")
    unmarked = commit("docs: say hello again\n\nWhy.\n\nProvenance: requested\n\n#{FOOTER}\n")
    [marked, unmarked]
  end

  def test_the_commits_since_origin_trunk_are_the_ones_checked
    marked, unmarked = two_commits
    check = FastCheck.new(root: @root)

    assert_equal [@base, [unmarked, marked]], [check.base, check.commits]
  end

  def test_a_commit_whose_provenance_trailer_git_does_not_parse_fails
    marked, unmarked = two_commits
    check = FastCheck.new(root: @root)

    assert_equal [unmarked], check.unmarked
    problem = check.problem(unmarked)
    assert_includes problem, unmarked[0, 12]
    assert_includes problem, "docs: say hello again"
    assert_includes problem, "no blank line"
    refute_includes check.unmarked, marked
  end

  def test_the_files_changed_since_the_base_and_in_the_working_tree_are_linted
    two_commits
    write("sig/old.rbs" => "class Old\n  def x: () -> void\nend\n")
    check = FastCheck.new(root: @root)

    assert_equal %w[README.md lib/new.rb sig/old.rbs], check.changed
    assert_predicate check, :typed?
    assert_equal %w[lib/new.rb], check.ruby(%w[lib/new.rb Rakefile gone.rb])
  end

  def test_a_base_it_is_given_comes_before_origin_trunk
    marked, unmarked = two_commits

    assert_equal [unmarked], FastCheck.new(root: @root, base: marked).commits
  end

  def test_with_no_base_known_it_checks_the_last_commit_alone
    write("README.md" => "bye\n")
    last = commit("docs: say bye\n\nProvenance: requested\n#{FOOTER}\n")
    check = FastCheck.new(root: @root)

    assert_equal [nil, [last], [], %w[README.md]], [check.base, check.commits, check.unmarked, check.changed]
    refute_predicate check, :typed?
  end
end
