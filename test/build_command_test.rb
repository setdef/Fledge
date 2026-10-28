# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "stringio"

# fledge build's arguments, through real streams, with runtimes from a
# FLEDGE_RUNTIME_DIR of fake runtimes.
class BuildCommandTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @runtimes = File.join(@dir, "runtimes")
    FileUtils.mkdir_p(@runtimes)
    Fledge::Platform.names.each { |name| FakeRuntime.write(@runtimes, Fledge::Platform.find(name)) }
    @app = FakeApp.write(@dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def build(*argv, host: Gem::Platform.new("x86_64-linux"), env: { "FLEDGE_RUNTIME_DIR" => @runtimes })
    out = StringIO.new
    err = StringIO.new
    status = Dir.chdir(@dir) { Fledge::CLI::Build.new(out:, err:, env:, host:).call(argv) }
    [out.string, err.string, status]
  end

  def test_the_build_is_for_this_computer_and_the_default_out_is_dist
    out, err, status = build("hello", host: Gem::Platform.new("arm64-darwin-25"))

    assert_equal [0, ""], [status, err]
    assert_equal "dist/Hello-arm64-darwin.tar.gz\n", out
    assert_path_exists File.join(@dir, "dist/Hello-arm64-darwin/Hello")
  end

  def test_on_another_computer_the_build_is_for_that_computer
    out, err, status = build("hello", host: Gem::Platform.new("aarch64-linux"))

    assert_equal [0, "", "dist/Hello-aarch64-linux.tar.gz\n"], [status, err, out]
  end

  def test_out_and_path_take_their_equals_and_double_dash_forms
    out, _, status = build("--out=elsewhere", "--", "hello")

    assert_equal 0, status
    assert_equal "elsewhere/Hello-x86_64-linux.tar.gz\n", out
  end

  def test_the_path_defaults_to_the_current_directory
    out = StringIO.new
    status = Dir.chdir(@app) do
      Fledge::CLI::Build.new(out:, err: StringIO.new, env: { "FLEDGE_RUNTIME_DIR" => @runtimes },
        host: Gem::Platform.new("x86_64-linux")).call(["-o", "../dist"])
    end

    assert_equal 0, status
    assert_equal "../dist/Hello-x86_64-linux.tar.gz\n", out.string
  end

  # Usage errors are the command line's to report, with the usage and
  # exit status 2 (Fledge::CLI), so the command raises them.
  def test_usage_mistakes_raise_a_usage_error
    {
      %w[-t x86_64-linux hello] => "-t is gone: a build is for this computer. Build each platform's app on that platform.",
      %w[--target=x64-mingw-ucrt hello] => "--target is gone: a build is for this computer. Build each platform's app on that platform.",
      %w[--out] => "--out needs a DIR",
      %w[--out=] => "--out needs a DIR",
      %w[--frobnicate hello] => "unrecognized option '--frobnicate'",
      %w[hello other] => "takes one PATH, but got 'hello' and 'other'",
    }.each do |argv, message|
      error = assert_raises(Fledge::UsageError, argv.inspect) { build(*argv) }
      assert_equal message, error.message, argv.inspect
    end
  end

  def test_build_failures_print_one_line_and_exit_one
    {
      %w[nowhere] => "fledge build: nowhere does not exist. Build the program you run, such as exe/my_app or main.rb.\n",
      %w[-o hello hello] => "fledge build: --out can't be the app's own folder, hello\n",
    }.each do |argv, message|
      out, err, status = build(*argv)

      assert_equal [1, "", message], [status, out, err], argv.inspect
    end
  end

  def test_a_computer_with_no_runtime_cannot_build
    _, err, status = build("hello", host: Gem::Platform.new("x86_64-linux-musl"))

    assert_equal 1, status
    assert_equal "fledge build: Fledge has no runtime for this computer's platform (x86_64-linux-musl). " \
      "Build on one it has: arm64-darwin, x86_64-linux, aarch64-linux, x64-mingw-ucrt.\n", err
  end

  def test_a_missing_runtime_is_an_error
    FileUtils.rm_f(File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::Platform.find("aarch64-linux"))))

    _, err, status = build("hello", host: Gem::Platform.new("aarch64-linux"))

    assert_equal 1, status
    assert_equal "fledge build: FLEDGE_RUNTIME_DIR is #{@runtimes}, which has no " \
      "fledge-runtime-#{Fledge::VERSION}-aarch64-linux.tar.gz\n", err
  end

  # A windowed app's installer (ADR 009) is printed after its archive.
  def test_a_windowed_apps_installer_follows_its_archive
    linux = Fledge::Platform.find("x86_64-linux")
    FakeRuntime.write(@runtimes, linux, extra: [Fledge::Entry.file("installer/appimage-runtime", "\x7FELF", mode: 0o755)])
    File.write(File.join(@app, "fledge.yml"), "name: Hello Window\nkind: windowed\nidentifier: com.example.HelloWindow\n")

    out, err, status = build("hello")

    assert_equal [0, ""], [status, err]
    assert_equal "dist/Hello Window-x86_64-linux.tar.gz\ndist/Hello Window-x86_64-linux.AppImage\n", out
  end

  # An NSIS installer needs makensis for this computer, from where the
  # runtimes come from; without one, the build says how to go on.
  def test_an_nsis_installer_without_makensis_says_what_to_do
    File.write(File.join(@app, "fledge.yml"), "name: Hello Window\nkind: windowed\nidentifier: com.example.HelloWindow\n")

    _, err, status = build("hello", host: Gem::Platform.new("x64-mingw-ucrt"))

    assert_equal 1, status
    assert_equal "fledge build: FLEDGE_RUNTIME_DIR is #{@runtimes}, which has no fledge-makensis-#{Fledge::VERSION}-x64-mingw-ucrt.tar.gz\n" \
      "fledge build: An NSIS installer needs makensis for this computer; set installers in fledge.yml to build without one.\n", err
  end

  def test_the_callers_arguments_are_left_unchanged
    argv = %w[-o dist hello].freeze

    Dir.chdir(@dir) do
      Fledge::CLI::Build.new(out: StringIO.new, err: StringIO.new, env: { "FLEDGE_RUNTIME_DIR" => @runtimes }).call(argv)
    end

    assert_equal %w[-o dist hello], argv
  end
end
