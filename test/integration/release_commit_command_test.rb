# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../test_helper"

# tasks/release_commit.rb as the pin watch's Pick job runs it, as a
# subprocess: "pending" exits by whether a CHANGELOG has anything to
# release.
class ReleaseCommitCommandTest < Minitest::Test
  SCRIPT = File.expand_path("../../tasks/release_commit.rb", __dir__)
  EMPTY = "# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - 2026-01-01\n\n- Old.\n"

  def run_pending(text)
    Dir.mktmpdir do |dir|
      file = File.join(dir, "CHANGELOG.md")
      File.write(file, text)
      out, status = Open3.capture2e(RbConfig.ruby, SCRIPT, "pending", file)
      [out, status.exitstatus]
    end
  end

  def test_exits_zero_when_there_is_something_to_release
    assert_equal 0, run_pending(EMPTY.sub("[Unreleased]\n", "[Unreleased]\n\n### Fixed\n\n- A fix.\n")).last
  end

  def test_exits_one_and_says_why_when_there_is_nothing
    out, code = run_pending(EMPTY)
    assert_equal 1, code
    assert_match(/nothing under \[Unreleased\]/, out)
  end
end
