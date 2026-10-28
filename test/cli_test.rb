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

  USAGE = "Usage: fledge build [OPTIONS] [PATH]\n" \
    "       fledge --help\n" \
    "       fledge --version\n" \
    "Try 'fledge --help'.\n"

  # GNU Coding Standards, section 4.8: --help and --version print to
  # standard output and succeed. -? is the Windows habit (dotnet, winget).
  def test_help_flags_print_the_executables_header_without_comment_markers
    %w[--help -h -?].each do |flag|
      out, err, status = fledge(flag)

      assert_equal 0, status
      assert_empty err
      assert_match(/\A=+\nfledge - Ship a Ruby app to people who don't have Ruby\n=+\n\n/, out)
      assert_includes out, "\nSYNOPSIS\n    fledge build [OPTIONS] [PATH]\n"
      assert_includes out, "    -v, --version      Print Fledge's version\n"
      assert_includes out, "    -h, -?, --help     Show this help\n"
      refute_match(/^#/, out)
      refute_includes out, "SPDX"
      refute_includes out, "fledge/cli"
    end
  end

  # The help is the CLI's contract, so it must name every platform Fledge
  # builds on, and the archive each gets.
  def test_help_names_every_platform_and_its_archive
    out, = fledge("--help")
    files = out[/^FILES\n(.*?)^ENVIRONMENT\n/m, 1].to_s.split.join(" ")

    assert_includes files, "PLATFORM is this computer's: #{Fledge::Platform.names.join(', ')}."
    assert_includes out, "DIR/NAME-PLATFORM.zip\n"
    assert_includes out.split.join(" "), "a .zip for Windows, a .tar.gz for macOS and Linux."
  end

  def test_help_names_each_exit_status
    out, = fledge("--help")
    statuses = out[/^EXIT STATUS\n(.*?)^EXAMPLES\n/m, 1].to_s

    assert_match(/^    0 +Success/, statuses)
    assert_match(/^    1 +The build failed/, statuses)
    assert_match(/^    2 +Usage error/, statuses)
  end

  def test_help_ends_at_the_closing_marker
    out, = fledge("--help")

    assert out.end_with?("=\n"), "help should end with the header's closing rule"
  end

  # The source carries no provenance statement after the header, printed
  # or not.
  def test_the_executable_carries_no_provenance_statement
    source = File.read(EXE)

    refute_match(/requested|AI agent|generative/i, source)
  end

  def test_help_keeps_blank_lines_and_indentation
    out, = fledge("--help")

    assert_includes out, "\n\nDESCRIPTION\n    Put a Ruby app"
  end

  # -v as ruby, gem, and bundle have it.
  def test_version_flags_print_the_version
    %w[--version -v].each do |flag|
      out, err, status = fledge(flag)

      assert_equal 0, status
      assert_empty err
      assert_equal "fledge #{Fledge::VERSION}\n", out
    end
  end

  def test_the_short_usage_is_the_help_headers_synopsis
    assert_equal "Usage: fledge build [OPTIONS] [PATH]\n       fledge --help\n       fledge --version\n",
      Fledge::CLI.new(help_path: EXE).usage
  end

  # A bare fledge asked for nothing: a usage error, as for GNU tools,
  # with exit status 2 rather than 1, which means an operation failed.
  def test_no_arguments_print_the_usage_to_standard_error_with_status_two
    out, err, status = fledge

    assert_equal 2, status
    assert_empty out
    assert_equal USAGE, err
  end

  def test_an_unknown_command_is_a_usage_error
    out, err, status = fledge("frobnicate", "now")

    assert_equal 2, status
    assert_empty out
    assert_equal "fledge: 'frobnicate' is not a fledge command\n#{USAGE}", err
  end

  def test_an_unknown_option_is_a_usage_error
    %w[--frobnicate -x -V].each do |option|
      out, err, status = fledge(option)

      assert_equal 2, status
      assert_empty out
      assert_equal "fledge: unrecognized option '#{option}'\n#{USAGE}", err
    end
  end

  def test_a_commands_usage_error_gets_the_usage_too
    out, err, status = fledge("build", "--frobnicate")

    assert_equal 2, status
    assert_empty out
    assert_equal "fledge build: unrecognized option '--frobnicate'\n#{USAGE}", err
  end

  # Each platform's app is built on that platform (ADR 010), so the
  # --target of Fledge 0.0.1.pre.7 is a usage error that says so.
  def test_a_target_is_a_usage_error_that_says_to_build_on_that_platform
    out, err, status = fledge("build", "--target", "x86_64-linux", "examples/hello")

    assert_equal 2, status
    assert_empty out
    assert_equal "fledge build: --target is gone: a build is for this computer. " \
      "Build each platform's app on that platform.\n#{USAGE}", err
  end

  def test_a_build_that_fails_exits_with_status_one_and_no_usage
    Dir.mktmpdir do |dir|
      out, err, status = fledge("build", dir)

      assert_equal 1, status
      assert_empty out
      assert_equal "fledge build: #{dir} is a folder with no main.rb, and its project names no one program to ship. " \
        "Build the program you run, such as fledge build #{File.join(dir, 'exe', 'my_app')}.\n", err
    end
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

    assert_equal 2, status
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
