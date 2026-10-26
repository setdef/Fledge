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
    out, err, status = build("-t", "arm64-darwin", "--target", "x86_64-linux", "--target=aarch64-linux", "-o", "builds", "hello")

    assert_equal [0, ""], [status, err]
    assert_equal "builds/hello-arm64-darwin.tar.gz\nbuilds/hello-x86_64-linux.tar.gz\nbuilds/hello-aarch64-linux.tar.gz\n", out
    %w[arm64-darwin x86_64-linux aarch64-linux].each do |name|
      assert_path_exists File.join(@dir, "builds/hello-#{name}.tar.gz")
    end
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

  def test_mistakes_print_one_line_and_exit_one
    {
      %w[-t sparc-solaris hello] => "fledge build: 'sparc-solaris' is not a target Fledge builds for. " \
        "Targets: arm64-darwin, x86_64-linux, aarch64-linux.\n",
      %w[hello -t] => "fledge build: -t needs a PLATFORM. See 'fledge --help'.\n",
      %w[--out] => "fledge build: --out needs a DIR. See 'fledge --help'.\n",
      %w[--frobnicate hello] => "fledge build: unknown option '--frobnicate'. See 'fledge --help'.\n",
      %w[hello other] => "fledge build: takes one PATH, but got 'hello' and 'other'\n",
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
      "Choose a target with --target: arm64-darwin, x86_64-linux, aarch64-linux.\n", err
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
