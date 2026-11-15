# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"
require "yaml"

# Every checkout has the line endings the repository holds, whatever
# core.autocrlf says, and RuboCop asks for those, not the system's own,
# so a lint gives the same verdict on Windows as on macOS and Linux
# (.gitattributes, .rubocop.yml).
class LineEndingsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def git(*)
    out, status = Open3.capture2("git", *, chdir: ROOT)
    assert_predicate status, :success?
    out
  end

  def test_git_checks_out_text_with_lf_on_every_system
    out = git("check-attr", "eol", "--", "lib/fledge.rb", "exe/fledge", "README.md", "bin/setup.ps1")

    assert_equal 4, out.lines.grep(/: eol: lf$/).size, out
  end

  # A file the repository holds with CRLF, such as the Windows batch file
  # Gradle generates, is checked out byte for byte, as git holds it.
  def test_only_files_kept_byte_for_byte_hold_crlf
    crlf = git("ls-files", "--eol").lines.select { |line| line.start_with?("i/crlf") }

    refute_empty crlf
    crlf.each { |line| assert_includes line, "attr/-text", line }
  end

  def test_rubocop_asks_for_lf_on_every_system
    config = YAML.safe_load_file(File.join(ROOT, ".rubocop.yml"))

    assert_equal "lf", config.dig("Layout/EndOfLine", "EnforcedStyle")
  end
end
