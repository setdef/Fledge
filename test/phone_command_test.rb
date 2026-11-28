# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "stringio"
require "tmpdir"
require "fledge/cli"

# fledge ios and fledge android: how each reads its command, project or
# run, and what run does with the project it writes and the status the
# app's program ends with. test/mobile_build_test.rb writes projects,
# and test/integration/phone_test_command_test.rb runs programs on a
# Simulator and an emulator.
class PhoneCommandTest < Minitest::Test
  EXE = File.expand_path("../exe/fledge", __dir__)
  Run = Fledge::CLI::Phone::Run
  IOS = Fledge::MobilePlatform.new(name: "ios")
  ANDROID = Fledge::MobilePlatform.new(name: "android")

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "fledge.yml"), "name: Basket\nidentifier: com.example.Basket\n")
    FileUtils.mkdir_p(File.join(@dir, "test"))
    @program = File.join(@dir, "test", "phone.rb")
    File.write(@program, "puts 1\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Runs fledge with +argv+ and returns its standard output, standard
  # error, and exit status.
  def fledge(*argv)
    out = StringIO.new
    err = StringIO.new
    status = Fledge::CLI.new(help_path: EXE, out:, err:).call(argv)
    [out.string, err.string, status]
  end

  def test_each_phone_is_a_command_of_fledge
    Fledge::MobilePlatform.names.each do |name|
      assert_equal Fledge::CLI::Phone::Command.new(phone: Fledge::MobilePlatform.new(name:)), Fledge::CLI::COMMANDS.fetch(name)
    end
  end

  # A phone's command needs one of its own, as Usage's
  # subcommand_required has it.
  def test_a_phone_without_a_command_is_a_usage_error
    out, err, status = fledge("ios")

    assert_equal [2, ""], [status, out]
    assert_match(/\Afledge ios: needs a command, project or run, such as fledge ios project\nUsage: /, err)
  end

  def test_an_unknown_command_of_a_phone_is_a_usage_error
    _, err, status = fledge("android", "frobnicate")

    assert_equal 2, status
    assert_match(/\Afledge android: 'frobnicate' is not a fledge android command: it takes project or run\n/, err)
  end

  # A mistake in project's or run's arguments names that command.
  def test_a_commands_usage_error_names_the_phone_and_the_command
    {
      %w[ios project --sign me] => "fledge ios project: --sign signs desktop apps; sign a phone's app with Xcode or Gradle\n",
      %w[android project a b] => "fledge android project: takes one PATH, but got 'a' and 'b'\n",
      %w[ios run --frobnicate] => "fledge ios run: unrecognized option '--frobnicate'\n",
    }.each do |argv, first|
      _, err, status = fledge(*argv)

      assert_equal 2, status, argv.inspect
      assert_equal first, err.lines.first
    end
  end

  # project's PATH is a path, whatever its name.
  def test_project_reads_a_phones_name_as_a_path
    assert_equal "android", Fledge::CLI::Build::Options.parse(%w[android], phone: "ios").path
    assert_equal ".", Fledge::CLI::Build::Options.parse(%w[-o out], phone: "ios").path
  end

  def test_run_reads_one_path_and_its_options
    assert_equal Run::Options.new(path: ".", out: "dist/test", device: nil), Run::Options.parse([])
    assert_equal Run::Options.new(path: "test/phone.rb", out: "dist/test", device: nil), Run::Options.parse(%w[test/phone.rb])
    assert_equal Run::Options.new(path: "ios", out: "o", device: "emulator-5554"), Run::Options.parse(%w[-o o -d emulator-5554 -- ios])
    assert_equal Run::Options.new(path: "t.rb", out: "o", device: "U"), Run::Options.parse(%w[--out=o t.rb --device=U])
  end

  def test_runs_arguments_are_refused_as_usage_errors
    {
      %w[a.rb b.rb] => /takes one PATH, but got 'a.rb' and 'b.rb'/,
      %w[a.rb --sign x] => /unrecognized option '--sign'/,
      %w[a.rb -o] => /-o needs a DIR/,
      %w[a.rb --device] => /--device needs an ID/,
    }.each do |argv, message|
      assert_match message, assert_raises(Fledge::UsageError, argv.inspect) { Run::Options.parse(argv) }.message
    end
  end

  # Runs fledge PHONE run with +argv+, building with +built+ (the status
  # the build returns, the project's folder printed) and running with
  # +status+, and returns its status, what it printed to the error
  # stream, and what build and run were given.
  def run_command(argv, phone: IOS, built: 0, status: 0)
    err = StringIO.new
    calls = []
    build = lambda do |arguments, printed|
      calls << [:build, arguments]
      printed.puts File.join(@dir, "dist", "test", "Basket-ios")
      built
    end
    run = lambda do |platform, app, project, device|
      calls << [:run, platform.name, app.name, app.identity.identifier, project, device]
      status
    end
    result = Run.new(out: StringIO.new, err:, phone:, build:, run:).call(argv)
    [result, err.string, calls]
  end

  def test_run_writes_the_project_with_the_program_in_place_of_the_apps_then_runs_it
    status, _, calls = run_command(["-o", File.join(@dir, "dist", "test"), "-d", "U1", @program])

    assert_equal 0, status
    assert_equal [
      [:build, ["--out", File.join(@dir, "dist", "test"), "--", @program]],
      [:run, "ios", "Basket", "com.example.Basket", File.join(@dir, "dist", "test", "Basket-ios"), "U1"],
    ], calls
  end

  # Without a PATH, run runs the app's own program, from the folder it
  # runs in.
  def test_run_without_a_path_runs_the_apps_program
    File.write(File.join(@dir, "main.rb"), "puts 2\n")
    _, _, calls = Dir.chdir(@dir) { run_command([], phone: ANDROID) }

    assert_equal [:build, ["--out", "dist/test", "--", "."]], calls.first
    assert_equal "android", calls.last[1]
  end

  def test_run_exits_with_the_programs_status
    assert_equal 1, run_command([@program], phone: ANDROID, status: 1).first
    assert_equal 42, run_command([@program], phone: ANDROID, status: 42).first
  end

  def test_a_status_a_shell_cannot_report_is_a_failure
    assert_equal 1, run_command([@program], status: 256).first, "256 would reach a shell as 0"
    assert_equal 1, run_command([@program], status: -1).first
  end

  def test_a_failed_build_runs_nothing
    status, _, calls = run_command([@program], built: 1)

    assert_equal 1, status
    assert_equal [:build], calls.map(&:first)
  end

  def test_a_failure_to_run_says_so_naming_the_command
    err = StringIO.new
    run = -> (*) { raise Fledge::Error, "No Simulator is booted." }
    status = Run.new(out: StringIO.new, err:, phone: IOS, build: -> (_, printed) { printed.puts(@dir) || 0 }, run:).call([@program])

    assert_equal 1, status
    assert_equal "fledge ios run: No Simulator is booted.\n", err.string
  end

  def test_a_missing_program_says_so_before_anything_is_built
    status, err, calls = run_command([File.join(@dir, "test", "nothing.rb")], phone: ANDROID)

    assert_equal 1, status
    assert_match(/\Afledge android run: .*nothing\.rb does not exist/, err)
    assert_empty calls
  end
end
