# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "stringio"
require "tmpdir"
require "fledge/cli"

# The fledge executable's argument handling, through real output
# streams. test/exe_test.rb runs the executable itself.
class CLITest < Minitest::Test
  EXE = File.expand_path("../exe/fledge", __dir__)

  # Runs the CLI with +argv+ against exe/fledge's help header and returns
  # its standard output, standard error, and exit status.
  def fledge(*argv, help_path: EXE)
    out = StringIO.new
    err = StringIO.new
    status = Fledge::CLI.new(help_path:, out:, err:).call(argv)
    [out.string, err.string, status]
  end

  def test_help_flags_print_the_executables_header_without_comment_markers
    %w[--help -h].each do |flag|
      out, err, status = fledge(flag)

      assert_equal 0, status
      assert_empty err
      assert_match(/\A=+\nfledge - Ship a Ruby app to people who don't have Ruby\n=+\n\n/, out)
      assert_includes out, "\nSYNOPSIS\n    fledge build [OPTIONS] [PATH]\n"
      assert_includes out, "    -V, --version      Print Fledge's version\n"
      refute_match(/^#/, out)
      refute_includes out, "SPDX"
      refute_includes out, "fledge/cli"
    end
  end

  def test_help_ends_at_the_closing_marker
    out, = fledge("--help")

    assert out.end_with?("=\n"), "help should end with the header's closing rule"
    refute_includes out, "Fledge is requested"
  end

  def test_help_keeps_blank_lines_and_indentation
    out, = fledge("--help")

    assert_includes out, "\n\nDESCRIPTION\n    Put a Ruby app"
  end

  def test_version_flags_print_the_version
    %w[--version -V].each do |flag|
      out, err, status = fledge(flag)

      assert_equal 0, status
      assert_empty err
      assert_equal "fledge #{Fledge::VERSION}\n", out
    end
  end

  def test_no_arguments_print_help_to_standard_error_and_fail
    out, err, status = fledge

    assert_equal 1, status
    assert_empty out
    assert_equal fledge("--help").first, err
  end

  def test_an_unknown_command_names_fledge_help
    out, err, status = fledge("frobnicate", "now")

    assert_equal 1, status
    assert_empty out
    assert_equal "fledge: 'frobnicate' is not a command. See 'fledge --help'.\n", err
  end

  def test_an_unknown_option_names_fledge_help
    %w[--frobnicate -x].each do |option|
      out, err, status = fledge(option)

      assert_equal 1, status
      assert_empty out
      assert_equal "fledge: unknown option '#{option}'. See 'fledge --help'.\n", err
    end
  end

  def test_build_reports_its_own_mistakes_through_the_error_stream
    out, err, status = fledge("build", "--target", "sparc-solaris", "examples/hello")

    assert_equal 1, status
    assert_empty out
    assert_equal "fledge build: 'sparc-solaris' is not a target Fledge builds for. " \
      "Targets: arm64-darwin, x86_64-linux, aarch64-linux.\n", err
  end

  def test_the_command_table_names_every_command
    assert_equal ["build"], Fledge::CLI::COMMANDS.keys
    assert_predicate Fledge::CLI::COMMANDS, :frozen?
  end

  def test_a_command_receives_the_arguments_after_its_name_and_the_streams
    received = nil
    command = Class.new do
      define_method(:initialize) { |out:, err:| received = { out:, err: } }
      define_method(:call) do |argv|
        received[:argv] = argv
        received[:out].puts "ran"
        7
      end
    end
    out = StringIO.new
    err = StringIO.new

    status = Fledge::CLI.new(help_path: EXE, out:, err:, commands: { "go" => command }).call(%w[go a b])

    assert_equal 7, status
    assert_equal %w[a b], received[:argv]
    assert_same err, received[:err]
    assert_equal "ran\n", out.string
  end

  # A frozen ARGV-like Array raises FrozenError if the CLI shifts it.
  def test_the_callers_arguments_are_left_unchanged
    argv = %w[build --frobnicate].freeze

    status = Fledge::CLI.new(help_path: EXE, out: StringIO.new, err: StringIO.new).call(argv)

    assert_equal 1, status
    assert_equal %w[build --frobnicate], argv
  end

  def test_a_file_without_a_help_header_is_an_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "tool")
      File.write(path, "#!/usr/bin/env ruby\n# no header here\n")

      error = assert_raises(ArgumentError) { fledge("--help", help_path: path) }
      assert_equal "#{path} has no help header between #### and ### lines", error.message
    end
  end
end
