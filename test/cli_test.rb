# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "stringio"
require "tmpdir"
require "fledge/cli"

# The fledge executable's argument handling, through real output
# streams. test/integration/exe_test.rb runs the executable itself.
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
    "       fledge build --from APP [OPTIONS] [PATH]\n" \
    "       fledge build ios|android [OPTIONS] [PATH]\n" \
    "       fledge test ios|android [OPTIONS] PROGRAM\n" \
    "       fledge --help\n" \
    "       fledge --version\n" \
    "Try 'fledge --help'.\n"

  # GNU Coding Standards, section 4.8: --help and --version print to
  # standard output and succeed.
  def test_help_flags_print_the_executables_header_without_comment_markers
    %w[--help -h].each do |flag|
      out, err, status = fledge(flag)

      assert_equal 0, status
      assert_empty err
      assert_match(/\A=+\nfledge - Ship a Ruby app to people who don't have Ruby\n=+\n\n/, out)
      assert_includes out, "\nSYNOPSIS\n    fledge build [OPTIONS] [PATH]\n"
      assert_includes out, "    -V, --version      Print Fledge's version, as the first\n"
      assert_includes out, "    -h, --help         Show this help, anywhere before --\n"
      refute_match(/^#/, out)
      refute_includes out, "SPDX"
      refute_includes out, "fledge/cli"
    end
  end

  # A bare word Fledge reads as a platform is read so by every later
  # release, and the help says to write ./NAME for a folder of that name,
  # naming each word the parser takes today.
  def test_help_reserves_the_words_it_reads_as_platforms
    out, = fledge("--help")
    words = out.split.join(" ")

    assert_includes words, "A PATH that is a bare word Fledge reads as a platform, today #{Fledge::MobilePlatform.names.join(' and ')}, " \
      "is read as one, and so is each platform's word a later release adds; write ./NAME for a folder of that name."
    assert_includes words, "Changing identifier makes a new app to each system"
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

  # -V, as Usage and clap give a command line, which leaves -v free for
  # verbose (clig.dev, "Arguments and flags").
  def test_version_flags_print_the_version
    %w[--version -V].each do |flag|
      out, err, status = fledge(flag)

      assert_equal 0, status
      assert_empty err
      assert_equal "fledge #{Fledge::VERSION}\n", out
    end
  end

  def test_the_short_usage_is_the_help_headers_synopsis
    assert_equal "Usage: fledge build [OPTIONS] [PATH]\n       fledge build --from APP [OPTIONS] [PATH]\n       fledge build ios|android [OPTIONS] [PATH]\n       fledge test ios|android [OPTIONS] PROGRAM\n       fledge --help\n" \
      "       fledge --version\n",
      Fledge::CLI.new(help_path: EXE).usage
  end

  # A bare fledge asked for nothing, so it shows the help, as clap's
  # arg_required_else_help does for a Usage spec's: on standard error,
  # with exit status 2, a usage error's, so that a script that runs a
  # bare fledge by mistake fails.
  def test_no_arguments_print_the_help_to_standard_error_with_status_two
    out, err, status = fledge

    assert_equal 2, status
    assert_empty out
    assert_equal Fledge::CLI.new(help_path: EXE).help, err
  end

  # Help wins wherever it is asked for before --, whatever else the
  # command line holds (clig.dev, "Help").
  def test_help_after_a_command_prints_the_help
    [%w[build --help], %w[build -o dist -h], %w[test ios --help], %w[frobnicate -h], %w[--frobnicate --help]].each do |argv|
      out, err, status = fledge(*argv)

      assert_equal 0, status, argv.inspect
      assert_empty err
      assert_equal Fledge::CLI.new(help_path: EXE).help, out
    end
  end

  def test_help_after_two_dashes_is_the_commands_argument
    received = nil
    command = Class.new do
      define_method(:initialize) { |out:, err:| nil }
      define_method(:call) { |argv| (received = argv) && 0 }
    end

    status = Fledge::CLI.new(help_path: EXE, out: StringIO.new, err: StringIO.new, commands: { "go" => command }).call(%w[go -- --help -h])

    assert_equal 0, status
    assert_equal %w[-- --help -h], received
  end

  # The version is fledge's alone, so a command reads -V and --version as
  # options it does not have, as Usage gives them to the top level alone.
  def test_the_version_after_a_command_is_the_commands_usage_error
    %w[-V --version].each do |flag|
      out, err, status = fledge("build", flag)

      assert_equal 2, status
      assert_empty out
      assert_equal "fledge build: unrecognized option '#{flag}'\n#{USAGE}", err
    end
  end

  def test_an_unknown_command_is_a_usage_error
    out, err, status = fledge("frobnicate", "now")

    assert_equal 2, status
    assert_empty out
    assert_equal "fledge: 'frobnicate' is not a fledge command\n#{USAGE}", err
  end

  # fledge reads neither -v nor -?: -V prints the version, and -h the
  # help.
  def test_an_unknown_option_is_a_usage_error
    %w[--frobnicate -x -v -?].each do |option|
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

  # Each platform's app is built on that platform, so the
  # --target of Fledge 0.0.1.pre.7 is a usage error that says so.
  def test_a_target_is_a_usage_error_that_says_to_build_on_that_platform
    out, err, status = fledge("build", "--target", "x86_64-linux", "examples/hello")

    assert_equal 2, status
    assert_empty out
    assert_equal "fledge build: --target is gone: a build is for this computer. " \
      "Build each platform's app on that platform.\n#{USAGE}", err
  end

  # Its short form, -t, is the same usage error, by the name it was given.
  def test_a_short_target_is_the_same_usage_error
    out, err, status = fledge("build", "-t", "x86_64-linux", "examples/hello")

    assert_equal 2, status
    assert_empty out
    assert_equal "fledge build: -t is gone: a build is for this computer. " \
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
    assert_equal %w[build test], Fledge::CLI::COMMANDS.keys
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
