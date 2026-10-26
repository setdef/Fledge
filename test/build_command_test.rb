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

  def test_the_default_target_is_this_computer_and_the_default_out_is_dist
    out, err, status = build("hello", host: Gem::Platform.new("arm64-darwin-25"))

    assert_equal [0, ""], [status, err]
    assert_equal "dist/hello-arm64-darwin.tar.gz\n", out
    assert_path_exists File.join(@dir, "dist/hello-arm64-darwin/hello")
  end

  def test_every_target_builds_from_one_computer
    out, err, status = build("-t", "arm64-darwin", "--target", "x86_64-linux", "--target=aarch64-linux",
      "-t", "x64-mingw-ucrt", "-o", "builds", "hello")

    assert_equal [0, ""], [status, err]
    assert_equal "builds/hello-arm64-darwin.tar.gz\nbuilds/hello-x86_64-linux.tar.gz\n" \
      "builds/hello-aarch64-linux.tar.gz\nbuilds/hello-x64-mingw-ucrt.zip\n", out
    %w[arm64-darwin x86_64-linux aarch64-linux].each do |name|
      assert_path_exists File.join(@dir, "builds/hello-#{name}.tar.gz")
      assert_path_exists File.join(@dir, "builds/hello-#{name}/hello")
    end
    assert_path_exists File.join(@dir, "builds/hello-x64-mingw-ucrt.zip")
    assert_path_exists File.join(@dir, "builds/hello-x64-mingw-ucrt/hello.exe")
  end

  def test_the_default_target_on_windows_is_windows
    out, err, status = build("hello", host: Gem::Platform.new("x64-mingw-ucrt"))

    assert_equal [0, "", "dist/hello-x64-mingw-ucrt.zip\n"], [status, err, out]
  end

  def test_a_repeated_target_builds_once
    out, = build("-t", "x86_64-linux", "-t", "x86_64-linux", "hello")

    assert_equal "dist/hello-x86_64-linux.tar.gz\n", out
  end

  def test_out_and_path_take_their_equals_and_double_dash_forms
    out, _, status = build("--out=elsewhere", "--", "hello")

    assert_equal 0, status
    assert_equal "elsewhere/hello-x86_64-linux.tar.gz\n", out
  end

  def test_the_path_defaults_to_the_current_directory
    out = StringIO.new
    status = Dir.chdir(@app) do
      Fledge::CLI::Build.new(out:, err: StringIO.new, env: { "FLEDGE_RUNTIME_DIR" => @runtimes },
        host: Gem::Platform.new("x86_64-linux")).call(["-o", "../dist"])
    end

    assert_equal 0, status
    assert_equal "../dist/hello-x86_64-linux.tar.gz\n", out.string
  end

  # Usage errors are the command line's to report, with the usage and
  # exit status 2 (Fledge::CLI), so the command raises them.
  def test_usage_mistakes_raise_a_usage_error
    {
      %w[-t sparc-solaris hello] => "'sparc-solaris' is not a target Fledge builds for. " \
        "Targets: arm64-darwin, x86_64-linux, aarch64-linux, x64-mingw-ucrt.",
      %w[hello -t] => "-t needs a PLATFORM",
      %w[--out] => "--out needs a DIR",
      %w[--target=] => "--target needs a PLATFORM",
      %w[--frobnicate hello] => "unrecognized option '--frobnicate'",
      %w[hello other] => "takes one PATH, but got 'hello' and 'other'",
    }.each do |argv, message|
      error = assert_raises(Fledge::UsageError, argv.inspect) { build(*argv) }
      assert_equal message, error.message, argv.inspect
    end
  end

  def test_build_failures_print_one_line_and_exit_one
    {
      %w[nowhere] => "fledge build: nowhere is not a folder. An app is a folder with a main.rb.\n",
      %w[-o hello hello] => "fledge build: --out can't be the app's own folder, hello\n",
    }.each do |argv, message|
      out, err, status = build(*argv)

      assert_equal [1, "", message], [status, out, err], argv.inspect
    end
  end

  def test_an_unsupported_computer_needs_a_target
    _, err, status = build("hello", host: Gem::Platform.new("x86_64-linux-musl"))

    assert_equal 1, status
    assert_equal "fledge build: Fledge has no runtime for this computer's platform (x86_64-linux-musl). " \
      "Choose a target with --target: arm64-darwin, x86_64-linux, aarch64-linux, x64-mingw-ucrt.\n", err
  end

  def test_a_missing_runtime_is_an_error
    FileUtils.rm_f(File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::Platform.find("aarch64-linux"))))

    _, err, status = build("-t", "aarch64-linux", "hello")

    assert_equal 1, status
    assert_equal "fledge build: FLEDGE_RUNTIME_DIR is #{@runtimes}, which has no " \
      "fledge-runtime-#{Fledge::VERSION}-aarch64-linux.tar.gz\n", err
  end

  def test_the_callers_arguments_are_left_unchanged
    argv = %w[-t x86_64-linux hello].freeze

    Dir.chdir(@dir) do
      Fledge::CLI::Build.new(out: StringIO.new, err: StringIO.new, env: { "FLEDGE_RUNTIME_DIR" => @runtimes }).call(argv)
    end

    assert_equal %w[-t x86_64-linux hello], argv
  end
end
