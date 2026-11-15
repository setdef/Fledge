# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"

# What the fast check before a push (bin/check, rake check;
# CONTRIBUTING.md, "Before a push") reads from git: the commits about to
# be pushed, which of them git parses no Provenance trailer in, and the
# files they and the working tree change, which are the ones it lints.
# The commits are those since the base: the commit named, or else where
# HEAD left its upstream, or else origin/trunk; with none of these known,
# the last commit alone.
class FastCheck
  # Raised for a base that names no commit.
  class Error < StandardError; end

  # The trailer every commit carries (AGENTS.md, Provenance), as git
  # parses it.
  TRAILER = "Provenance"
  # Its value.
  PROVENANCE = "requested"
  # The files Steep checks.
  TYPED = %r{\A(?:lib/|sig/|Steepfile\z)}
  # The refs tried, in order, for a base no one names.
  BASES = %w[@{upstream} origin/trunk].freeze

  # A check of the repository at +root+, of the commits since +base+
  # (a commit or ref), or since BASES' first.
  def initialize(root:, base: nil)
    @root = root
    @named = base
  end

  # The commit the commits checked sit on, or nil when none is known.
  def base
    return @base if defined?(@base)

    @base = if @named
      merge_base(@named) or raise Error, "#{@named} names no commit"
    else
      BASES.lazy.filter_map { |ref| merge_base(ref) }.first
    end
  end

  # The commits checked, newest first.
  def commits
    @commits ||= base ? git("rev-list", "#{base}..HEAD").split : [git("rev-parse", "HEAD").strip]
  end

  # The commits checked whose message git parses no Provenance:
  # requested trailer in.
  def unmarked
    commits.reject do |commit|
      git("log", "-n1", "--format=%(trailers:key=#{TRAILER},valueonly,unfold)", commit).lines.map(&:strip).include?(PROVENANCE)
    end
  end

  # What is wrong with the unmarked +commit+, and how to fix it.
  def problem(commit)
    subject = git("log", "-n1", "--format=%s", commit).strip
    "commit #{commit[0, 12]} (#{subject}) has no \"#{TRAILER}: #{PROVENANCE}\" trailer that git parses: " \
      "put it in the message's last paragraph, with no blank line between it and the Co-Authored-By line, " \
      "and reword the commit before the push (git commit --amend, for the last one)"
  end

  # The files, relative to the root, that the commits checked and the
  # working tree change and that are still there, sorted.
  def changed
    @changed ||= git("diff", "--name-only", "--no-renames", "--diff-filter=d", "-z", since).split("\0").sort
  end

  # Whether a changed file is one Steep checks.
  def typed?
    changed.any? { |path| path.match?(TYPED) }
  end

  # The changed files among +targets+, the files RuboCop inspects.
  def ruby(targets)
    changed & targets
  end

  # What the working tree is compared with: the base, or else the last
  # commit's parent, or else, for a first commit, the empty tree.
  private def since
    return base if base

    parent = git?("rev-parse", "--verify", "--quiet", "HEAD^")
    parent ? parent.strip : git("hash-object", "-t", "tree", "--stdin", stdin: "").strip
  end

  private def merge_base(ref)
    git?("merge-base", ref, "HEAD")&.strip
  end

  private def git(*, stdin: nil)
    git?(*, stdin:) or raise Error, "git #{[*].join(' ')} failed in #{@root}"
  end

  private def git?(*, stdin: nil)
    out, _err, status = Open3.capture3("git", *, chdir: @root, stdin_data: stdin.to_s)
    out if status.success?
  end
end
