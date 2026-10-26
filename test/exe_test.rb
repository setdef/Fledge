# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

# exe/fledge as a person runs it: a process of its own, with its own
# standard streams and exit status. test/cli_test.rb covers each
# argument in process.
class ExeTest < Minitest::Test
  EXE = File.expand_path("../exe/fledge", __dir__)
  LIB = File.expand_path("../lib", __dir__)

  # Runs exe/fledge with warnings on, and returns its standard output,
  # standard error, and exit status. On Windows a process writes its
  # standard streams in text mode, ending lines with CRLF; the lines are
  # what matter here, so they are compared with LF endings everywhere.
  def run_fledge(*argv)
    out, err, status = Open3.capture3(RbConfig.ruby, "-W", "-I", LIB, EXE, *argv)
    [out.gsub("\r\n", "\n"), err.gsub("\r\n", "\n"), status]
  end

  def test_help_prints_the_header_and_succeeds
    out, err, status = run_fledge("--help")

    assert_predicate status, :success?, err
    assert_empty err
    assert_includes out, "fledge - Ship a Ruby app to people who don't have Ruby"
    assert_includes out, "EXIT STATUS"
  end

  def test_version_prints_the_version
    out, err, status = run_fledge("--version")

    assert_predicate status, :success?, err
    assert_equal "fledge #{Fledge::VERSION}\n", out
  end

  def test_build_without_an_app_exits_with_status_one
    Dir.mktmpdir do |dir|
      out, err, status = run_fledge("build", dir)

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "fledge build: #{dir} has no main.rb. An app is a folder with a main.rb.\n", err
    end
  end
end
