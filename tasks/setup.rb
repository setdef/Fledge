# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "rbconfig"

# Sets a checkout up for a contributor, on every system, in one file
# (CONTRIBUTING.md): installs the tools mise.toml pins, installs the
# gems Gemfile.lock locks, and builds the API documentation. A person
# types
#
#   mise trust -q mise.toml
#   mise x -- ruby tasks/setup.rb
#
# and bin/check runs it first. It holds no step of its own for any one
# system, and runs each command as an array of words, never through a
# shell, since on Windows RubyInstaller's Ruby starts a child by
# Windows' rules.
#
# It runs before the bundle exists, so it requires only Ruby's core and
# its default gems. It is safe to run before every check: with nothing
# missing it prints nothing, and a command it runs is shown, with its
# output, only when it installs or writes something, or fails. The first
# failure ends it with a non-zero status.
class Setup
  # What this file needs of the computer to start a command: runs +argv+
  # in +chdir+ with +env+ added to the environment, yields each line the
  # command writes, and says whether it succeeded. Tests give Setup a
  # recorder in its place.
  class Runner
    # Standard input is closed, so no command can wait for a person.
    def call(argv, env:, chdir:)
      IO.popen(env, argv, in: File::NULL, err: %i[child out], chdir:) { |io| io.each_line { |line| yield line } }
      Process.last_status.success?
    end
  end

  # The file whose lock keeps two setups from installing at once.
  LOCK_NAME = "fledge-setup.lock"

  attr_reader :root

  # +root+ is the checkout, +env+ the environment, +platform+ Ruby's
  # name for the system (RbConfig's host_os), and +home+ the person's
  # home folder.
  def initialize(root: File.expand_path("..", __dir__), env: ENV, runner: Runner.new, out: $stdout, err: $stderr,
    platform: RbConfig::CONFIG.fetch("host_os"), home: Dir.home
  )
    @root = root
    @env = env
    @runner = runner
    @out = out
    @err = err
    @platform = platform
    @home = home
  end

  # Sets the checkout up and returns the exit status: 0, or 1 at the
  # first command that fails.
  def run
    return 1 unless locked { install }

    # The documentation is for a contributor, not for CI.
    return 1 unless filled?("CI") || step(%w[mise x -- bundle exec rake rdoc], show: :failure)

    0
  rescue Errno::ENOENT
    @err.puts "mise isn't installed. Please install it to continue: https://mise.jdx.dev"
    1
  end

  # The file locked around the installs: in mise's cache folder, which
  # is where two setups at once break mise's download store.
  def lock_path = File.join(cache_home, "mise", LOCK_NAME)

  # On a CI-like machine (CI is set, as GitHub's runners and other CI
  # systems set it) the gems, and the Bundler the lockfile names, go
  # into the workspace, as ruby/setup-ruby's bundler-cache does, so that
  # runs sharing one Ruby never write its gem folder at once. A
  # BUNDLE_PATH the environment already names (CI's cached folder) wins.
  # On a contributor's computer nothing changes.
  private def workspace_bundle
    return if !filled?("CI") || filled?("BUNDLE_PATH")

    File.join(@root, "vendor", "bundle")
  end

  private def child_env = (path = workspace_bundle) ? { "BUNDLE_PATH" => path } : {}

  # Every tool mise.toml pins, whichever mise.*.toml MISE_ENV adds, and
  # the gems. mise install runs only when mise lists a tool missing, and
  # names none: naming one makes mise 2026.10.11 install every entry of
  # it whatever its os says. Later commands, such as bundle exec rake,
  # find the workspace's gems through .bundle/config, which git ignores.
  private def install
    missing = +""
    step(%w[mise ls --missing], show: :failure) { |line| missing << line } or return false
    (missing.strip.empty? || step(%w[mise install])) &&
      (workspace_bundle.nil? || step(["mise", "x", "--", "bundle", "config", "set", "--local", "path", workspace_bundle], announce: true)) &&
      (step(%w[mise x -- bundle check], show: :never) || step(%w[mise x -- bundle install]))
  end

  # Runs one command and says whether it succeeded, handing each line it
  # writes to the block. A command shown as :output is announced with
  # the shell's "+ " before its first line, as set -x does, and prints as
  # it goes; one shown as :failure keeps what it writes and prints it
  # only if the command fails, and one shown as :never not even then,
  # since its failure is an answer. A step +announce+d writes something,
  # so it is announced even when it prints nothing.
  private def step(argv, show: :output, announce: false)
    @out.puts "+ #{argv.join(' ')}" if announce
    shown = announce
    written = +""
    succeeded = @runner.call(argv, env: child_env, chdir: @root) do |line|
      yield line if block_given?
      if show == :output
        @out.puts "+ #{argv.join(' ')}" unless shown
        shown = true
        @out.print line
      else
        written << line
      end
    end
    return true if succeeded
    return false if show == :never

    @out.puts "+ #{argv.join(' ')}" unless shown
    @out.print written
    @err.puts "#{argv.join(' ')} failed"
    false
  end

  private def locked
    FileUtils.mkdir_p(File.dirname(lock_path))
    File.open(lock_path, File::RDWR | File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)
      yield
    end
  end

  # The XDG cache folder when the environment names one, else the
  # system's default.
  private def cache_home
    return @env.fetch("XDG_CACHE_HOME") if filled?("XDG_CACHE_HOME")

    case @platform
    when /mswin|mingw|cygwin/ then @env.fetch("LOCALAPPDATA") { File.join(@home, "AppData", "Local") }
    when /darwin/ then File.join(@home, "Library", "Caches")
    else File.join(@home, ".cache")
    end
  end

  private def filled?(name) = !@env.fetch(name, "").empty?
end

exit Setup.new.run if $PROGRAM_NAME == __FILE__
