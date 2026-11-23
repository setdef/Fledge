# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/setup"
require "stringio"

# What tasks/setup.rb does to a checkout, asserted on the commands it
# would run: a recorder takes the place of the command runner, so no
# process starts, and the test runs the same on Linux, macOS, and Windows.
class SetupTest < Minitest::Test
  # Stands in for Setup::Runner: records each command and the environment
  # it was given, answers from a script, and notes whether the install
  # lock was held when each command ran.
  class Recorder
    attr_reader :commands, :environments, :locked

    def initialize(lock_path: nil, fail_on: [], exit_with: {}, output: {}, raise_on: {})
      @lock_path = lock_path
      @fail_on = fail_on
      @exit_with = exit_with
      @output = output
      @raise_on = raise_on
      @commands = []
      @environments = []
      @locked = []
    end

    def call(argv, env:, chdir:)
      raise @raise_on.fetch(argv) if @raise_on.key?(argv)

      @commands << argv
      @environments << env
      @locked << held? if @lock_path
      Array(@output[argv]).each { |line| yield line }
      @exit_with.fetch(argv) { @fail_on.include?(argv) ? 1 : 0 }
    end

    private def held?
      File.open(@lock_path, File::RDWR | File::CREAT) { |other| other.flock(File::LOCK_EX | File::LOCK_NB) == false }
    end
  end

  MISSING = %w[mise ls --missing].freeze
  MISE_INSTALL = %w[mise install].freeze
  BUNDLE_CHECK = %w[mise x -- bundle check].freeze
  BUNDLE_INSTALL = %w[mise x -- bundle install].freeze
  RDOC = %w[mise x -- bundle exec rake rdoc].freeze

  def setup
    @cache = Dir.mktmpdir("setup-cache")
    @root = File.join(Dir.mktmpdir("setup-root"), "checkout")
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown
    FileUtils.rm_rf([@cache, File.dirname(@root)])
  end

  def lock_path = File.join(@cache, "mise", "fledge-setup.lock")

  def run_setup(env: {}, runner: Recorder.new)
    Setup.new(root: @root, env: { "XDG_CACHE_HOME" => @cache }.merge(env), runner:, out: @out, err: @err).run
  end

  def test_with_nothing_missing_it_installs_checks_the_bundle_builds_the_docs_and_says_nothing
    recorder = Recorder.new

    assert_equal 0, run_setup(runner: recorder)
    assert_equal [MISSING, BUNDLE_CHECK, RDOC], recorder.commands
    assert_equal "", @out.string
    assert_equal "", @err.string
  end

  def test_every_command_is_an_array_of_words_and_mise_install_names_no_tool
    recorder = Recorder.new(output: { MISSING => ["ruby 4.1.0-preview1 (missing)\n"] })
    run_setup(env: { "CI" => "true" }, runner: recorder)
    run_setup(runner: recorder)

    assert_includes recorder.commands, MISE_INSTALL
    assert(recorder.commands.all? { |argv| argv.all?(String) && argv.size > 1 })
    assert(recorder.commands.none? { |argv| argv.join(" ").match?(/&&|\|\||2>|\s>|\$\(|`/) })
  end

  def test_a_bundle_that_is_not_installed_is_installed_and_the_command_shown
    recorder = Recorder.new(fail_on: [BUNDLE_CHECK], output: { BUNDLE_INSTALL => ["Bundle complete!\n"] })

    assert_equal 0, run_setup(runner: recorder)
    assert_equal [MISSING, BUNDLE_CHECK, BUNDLE_INSTALL, RDOC], recorder.commands
    assert_equal "+ mise x -- bundle install\nBundle complete!\n", @out.string
  end

  def test_a_bundle_that_could_not_be_asked_about_stops_setup_and_shows_why_without_installing
    recorder = Recorder.new(exit_with: { BUNDLE_CHECK => 127 }, output: { BUNDLE_CHECK => ["mise ERROR bundle: command not found\n"] })

    assert_equal 1, run_setup(runner: recorder)
    assert_equal [MISSING, BUNDLE_CHECK], recorder.commands
    assert_equal "+ mise x -- bundle check\nmise ERROR bundle: command not found\n", @out.string
    assert_match(/bundle check failed/, @err.string)
  end

  def test_a_tool_that_is_missing_is_installed_and_the_command_shown_with_its_output
    recorder = Recorder.new(output: { MISSING => ["ruby 4.1.0-preview1 (missing)\n"], MISE_INSTALL => ["mise ruby@4.1.0-preview1 install\n"] })

    assert_equal 0, run_setup(runner: recorder)
    assert_equal [MISSING, MISE_INSTALL, BUNDLE_CHECK, RDOC], recorder.commands
    assert_equal "+ mise install\nmise ruby@4.1.0-preview1 install\n", @out.string
  end

  def test_the_docs_are_built_quietly_and_shown_only_when_they_fail
    run_setup(runner: Recorder.new(output: { RDOC => ["Parsing sources...\n"] }))

    assert_equal "", @out.string
    assert_equal 1, run_setup(runner: Recorder.new(fail_on: [RDOC], output: { RDOC => ["rdoc: error\n"] }))
    assert_equal "+ mise x -- bundle exec rake rdoc\nrdoc: error\n", @out.string
  end

  def test_on_ci_the_gems_go_into_the_workspace_and_later_commands_find_them
    recorder = Recorder.new
    path = File.join(@root, "vendor", "bundle")

    assert_equal 0, run_setup(env: { "CI" => "true" }, runner: recorder)
    assert_equal [MISSING, ["mise", "x", "--", "bundle", "config", "set", "--local", "path", path], BUNDLE_CHECK], recorder.commands
    assert(recorder.environments.all? { |env| env == { "BUNDLE_PATH" => path } })
    assert_equal "+ mise x -- bundle config set --local path #{path}\n", @out.string
  end

  def test_on_ci_a_bundle_path_the_environment_names_wins_and_is_not_written_down
    recorder = Recorder.new
    run_setup(env: { "CI" => "true", "BUNDLE_PATH" => File.join(@cache, "gems") }, runner: recorder)

    assert_equal [MISSING, BUNDLE_CHECK], recorder.commands
    assert(recorder.environments.all?(&:empty?))
  end

  def test_off_ci_nothing_changes_where_gems_go_and_the_docs_are_built
    recorder = Recorder.new
    run_setup(env: { "CI" => "" }, runner: recorder)

    assert(recorder.environments.all?(&:empty?))
    assert_includes recorder.commands, RDOC
  end

  def test_the_first_failure_is_shown_with_its_output_and_stops_setup
    recorder = Recorder.new(fail_on: [MISSING], output: { MISSING => ["mise ERROR bad config\n"] })

    assert_equal 1, run_setup(runner: recorder)
    assert_equal [MISSING], recorder.commands
    assert_equal "+ mise ls --missing\nmise ERROR bad config\n", @out.string
    assert_match(/mise ls --missing failed/, @err.string)
  end

  def test_a_failed_install_stops_setup
    recorder = Recorder.new(fail_on: [MISE_INSTALL], output: { MISSING => ["x (missing)\n"] })

    assert_equal 1, run_setup(runner: recorder)
    assert_equal [MISSING, MISE_INSTALL], recorder.commands
  end

  def test_a_missing_mise_says_so
    assert_equal 1, run_setup(runner: Recorder.new(raise_on: { MISSING => Errno::ENOENT.new("mise") }))
    assert_match(/mise isn't installed/, @err.string)
  end

  def test_the_install_steps_run_while_the_lock_is_held_and_the_docs_after_it
    FileUtils.mkdir_p(File.dirname(lock_path))
    recorder = Recorder.new(lock_path:)
    run_setup(runner: recorder)

    assert_equal [true, true, false], recorder.locked
  end

  def test_a_second_setup_waits_for_the_first
    FileUtils.mkdir_p(File.dirname(lock_path))
    ran = Queue.new
    File.open(lock_path, File::RDWR | File::CREAT) do |first|
      first.flock(File::LOCK_EX)
      second = Thread.new { run_setup(runner: -> (*, **) { ran << true; 0 }) }
      sleep 0.2

      assert_empty ran, "the second setup ran while the first held the lock"
      first.flock(File::LOCK_UN)
      second.join
    end
  end

  def test_the_lock_is_in_the_cache_folder_the_tools_use
    {
      [{ "XDG_CACHE_HOME" => "/xdg" }, "linux"] => "/xdg",
      [{}, "linux-gnu"] => "/home/someone/.cache",
      [{ "XDG_CACHE_HOME" => "" }, "linux"] => "/home/someone/.cache",
      [{}, "darwin25"] => "/home/someone/Library/Caches",
      [{ "LOCALAPPDATA" => "C:/Users/x/AppData/Local" }, "mingw-ucrt"] => "C:/Users/x/AppData/Local",
      [{}, "mswin64"] => "/home/someone/AppData/Local",
    }.each do |(env, platform), folder|
      setup = Setup.new(root: @root, env:, platform:, home: "/home/someone", runner: nil, out: @out, err: @err)

      assert_equal File.join(folder, "mise", "fledge-setup.lock"), setup.lock_path, [env, platform].inspect
    end
  end

  # The default gems of Ruby 4.1 (Gem::Specification.select(&:default_gem?)
  # in a Ruby with no bundle, which a test under Bundler cannot ask), and
  # the one library RbConfig is.
  DEFAULT_GEMS = %w[
    bundler
    date
    delegate
    did_you_mean
    digest
    english
    erb
    error_highlight
    etc
    fcntl
    fileutils
    find
    forwardable
    io-console
    io-nonblock
    ipaddr
    json
    net-http
    net-protocol
    open-uri
    open3
    openssl
    optparse
    pp
    prettyprint
    psych
    resolv
    ruby2_keywords
    securerandom
    shellwords
    singleton
    stringio
    strscan
    syntax_suggest
    tempfile
    time
    timeout
    tmpdir
    un
    uri
    weakref
    yaml
    zlib
    rbconfig
].freeze

  # Setup runs before the bundle exists, so it may load only Ruby's core
  # and its default gems (on Ruby 4, logger, csv, and fiddle are bundled
  # gems, which are not safely there).
  def test_it_requires_nothing_but_core_and_default_gems
    source = File.read(File.expand_path("../tasks/setup.rb", __dir__))
    required = source.scan(/^\s*require(?:_relative)?\s+["']([^"']+)["']/).flatten

    assert_empty required - DEFAULT_GEMS
  end
end
