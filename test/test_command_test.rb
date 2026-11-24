# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "stringio"
require "tmpdir"
require "fledge/cli"

# fledge test's arguments, and what it does with the project fledge build
# writes and the status the app's program ends with
# (doc/contributors/design/phone-projects.md, "Tests in the app").
# test/integration/phone_test_command_test.rb runs it on a Simulator and
# an emulator.
class TestCommandTest < Minitest::Test
  Options = Fledge::CLI::Test::Options

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

  def test_it_reads_the_phone_then_the_program
    assert_equal Options.new(phone: "ios", program: "test/phone.rb", out: "dist/test", device: nil), Options.parse(%w[ios test/phone.rb])
    assert_equal Options.new(phone: "android", program: "ios", out: "o", device: "emulator-5554"), Options.parse(%w[android -o o -d emulator-5554 -- ios])
    assert_equal Options.new(phone: "android", program: "t.rb", out: "o", device: "U"), Options.parse(%w[--out=o android t.rb --device=U])
  end

  def test_its_arguments_are_refused_as_usage_errors
    {
      %w[test/phone.rb] => /names the phone first, ios or android/,
      %w[ios] => /needs PROGRAM/,
      %w[ios a.rb b.rb] => /takes one PROGRAM, but got 'a.rb' and 'b.rb'/,
      %w[ios a.rb --sign x] => /unrecognized option '--sign'/,
      %w[ios a.rb -o] => /-o needs a DIR/,
      %w[ios a.rb --device] => /--device needs an ID/,
    }.each do |argv, message|
      assert_match message, assert_raises(Fledge::UsageError, argv.inspect) { Options.parse(argv) }.message
    end
  end

  def test_fledge_test_is_a_command_of_fledge
    err = StringIO.new
    status = Fledge::CLI.new(help_path: File.expand_path("../exe/fledge", __dir__), out: StringIO.new, err:).call(%w[test])

    assert_equal 2, status
    assert_match(/\Afledge test: names the phone first/, err.string)
  end

  # Runs fledge test with +argv+, building with +built+ (the status
  # fledge build returns, the project's folder printed) and running with
  # +status+, and returns its status, what it printed to the error
  # stream, and what build and run were given.
  def fledge_test(argv, built: 0, status: 0)
    err = StringIO.new
    calls = []
    build = lambda do |arguments, printed|
      calls << [:build, arguments]
      printed.puts File.join(@dir, "dist", "test", "Basket-ios")
      built
    end
    run = lambda do |phone, app, project, device|
      calls << [:run, phone.name, app.name, app.identity.identifier, project, device]
      status
    end
    result = Fledge::CLI::Test.new(out: StringIO.new, err:, build:, run:).call(argv)
    [result, err.string, calls]
  end

  def test_it_builds_the_project_with_the_program_in_place_of_the_apps_then_runs_it
    status, _, calls = fledge_test(["ios", "-o", File.join(@dir, "dist", "test"), "-d", "U1", @program])

    assert_equal 0, status
    assert_equal [
      [:build, ["ios", "--out", File.join(@dir, "dist", "test"), "--", @program]],
      [:run, "ios", "Basket", "com.example.Basket", File.join(@dir, "dist", "test", "Basket-ios"), "U1"],
    ], calls
  end

  def test_it_exits_with_the_programs_status
    assert_equal 1, fledge_test(["android", @program], status: 1).first
    assert_equal 42, fledge_test(["android", @program], status: 42).first
  end

  def test_a_status_a_shell_cannot_report_is_a_failure
    assert_equal 1, fledge_test(["android", @program], status: 256).first, "256 would reach a shell as 0"
    assert_equal 1, fledge_test(["android", @program], status: -1).first
  end

  def test_a_failed_build_runs_nothing
    status, _, calls = fledge_test(["ios", @program], built: 1)

    assert_equal 1, status
    assert_equal [:build], calls.map(&:first)
  end

  def test_a_failure_to_run_says_so
    err = StringIO.new
    run = -> (*) { raise Fledge::Error, "No Simulator is booted." }
    status = Fledge::CLI::Test.new(out: StringIO.new, err:, build: -> (_, printed) { printed.puts(@dir) || 0 }, run:).call(["ios", @program])

    assert_equal 1, status
    assert_equal "fledge test: No Simulator is booted.\n", err.string
  end

  def test_a_missing_program_says_so_before_anything_is_built
    status, err, calls = fledge_test(["ios", File.join(@dir, "test", "nothing.rb")])

    assert_equal 1, status
    assert_match(/\Afledge test: .*nothing\.rb does not exist/, err)
    assert_empty calls
  end
end
