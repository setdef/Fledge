# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"
require "stringio"

# examples/hello, built by fledge build from a real runtime for this
# computer, unpacked by the system's own tool (tar, or Expand-Archive on
# Windows), and run in a clean and in a hostile environment.
# .github/scripts/deliver.sh and deliver.ps1 run the same checks on fresh
# computers with no Ruby; this test runs them wherever a runtime is.
#
# The runtime comes from FLEDGE_RUNTIME_DIR, or from tmp/runtime, where
# rake runtime writes it. Without one the test skips, unless
# FLEDGE_REQUIRE_RUNTIME is set, as CI sets it on every platform with a
# runtime, so a missing runtime there fails instead of passing silently.
class BuiltAppTest < Minitest::Test
  HELLO = File.expand_path("../examples/hello", __dir__)
  EXE = File.expand_path("../exe/fledge", __dir__)
  LIB = File.expand_path("../lib", __dir__)

  def setup
    @platform = Fledge::Platform.local
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
    return if File.file?(File.join(@runtimes, Fledge::Runtimes.file_name(@platform)))

    message = "no #{Fledge::Runtimes.file_name(@platform)} in #{@runtimes}; run bundle exec rake runtime"
    flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip message
  rescue Fledge::Error => e
    flunk e.message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip e.message
  end

  def expected
    "Hello from Ruby 4.0.9 on #{expected_platform}\n"
  end

  # RUBY_PLATFORM as rv-ruby reports it: macOS builds carry the Darwin
  # version they were built for, macOS 14's.
  def expected_platform
    (@platform.name == "arm64-darwin") ? "arm64-darwin23" : @platform.name
  end

  # One build serves every test: building takes seconds.
  def app
    self.class.built ||= begin
      dir = Dir.mktmpdir
      Minitest.after_run { FileUtils.rm_rf(dir) }
      build_and_unpack(dir)
    end
  end

  class << self
    attr_accessor :built
  end

  def test_the_built_app_runs_with_no_ruby_environment
    Dir.mktmpdir do |dir|
      out, err, status = run_app({ "HOME" => dir }, app)

      assert_equal [expected, "", 0], [out, err, status.exitstatus]
    end
  end

  def test_the_built_app_ignores_a_hostile_ruby_environment
    Dir.mktmpdir do |dir|
      evil = File.join(dir, "evil")
      user_gems = File.join(dir, ".gem/ruby/4.0.0")
      FileUtils.mkdir_p([evil, File.join(user_gems, "gems/json-99.0.0/lib"), File.join(user_gems, "specifications")])
      leak = "raise 'the caller\\'s Ruby environment leaked into the app'\n"
      %w[json nonexistent bundler_setup].each { |name| File.write(File.join(evil, "#{name}.rb"), leak) }
      File.write(File.join(user_gems, "gems/json-99.0.0/lib/json.rb"), leak)
      File.write(File.join(user_gems, "specifications/json-99.0.0.gemspec"), <<~SPEC)
        Gem::Specification.new { |s| s.name = "json"; s.version = "99.0.0"; s.summary = "x"; s.authors = ["x"]; s.files = ["lib/json.rb"] }
      SPEC
      env = {
        "HOME" => dir,
        "RUBYLIB" => evil,
        "RUBYOPT" => "-rnonexistent",
        "GEM_HOME" => user_gems,
        "GEM_PATH" => user_gems,
        "BUNDLE_GEMFILE" => File.join(evil, "Gemfile"),
        "BUNDLER_SETUP" => File.join(evil, "bundler_setup.rb"),
        "RUBYGEMS_GEMDEPS" => "-",
        # RubyInstaller's: folders to load DLLs from, and putting them on
        # PATH. Windows' variable names ignore case, so a lowercase
        # bundle_ variable is Bundler's too.
        "RUBY_DLL_PATH" => evil,
        "RI_FORCE_PATH_FOR_DLL" => "1",
        "bundle_gemfile" => File.join(evil, "Gemfile"),
      }

      out, err, status = run_app(env, app)

      assert_equal [expected, "", 0], [out, err, status.exitstatus]
    end
  end

  def test_the_apps_exit_status_reaches_the_caller
    Dir.mktmpdir do |dir|
      out, _, status = run_app({ "HOME" => dir }, app, "3")

      assert_equal [expected, 3], [out, status.exitstatus]
    end
  end

  # Builds hello through the fledge executable, as a person would, and
  # unpacks its archive under a path with spaces and characters outside
  # ASCII. Returns the launcher's path.
  def build_and_unpack(dir)
    out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes }, RbConfig.ruby, "-I", LIB, EXE, "build",
      "-o", File.join(dir, "dist"), HELLO)
    assert_predicate status, :success?, err
    archive = File.expand_path(out.chomp, Dir.pwd)

    place = File.join(dir, "My Apps", "Ünïcödé 日本")
    FileUtils.mkdir_p(place)
    unpack(archive, place)
    File.join(place, "hello-#{@platform}", @platform.executable("hello"))
  end

  # Windows' own Expand-Archive for a .zip, as a person on Windows has
  # it, and the system's tar for a .tar.gz.
  def unpack(archive, place)
    command = if @platform.windows?
      [
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "$ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $env:ARCHIVE -DestinationPath $env:PLACE",
]
    else
      ["tar", "-xzf", archive, "-C", place]
    end
    out, status = Open3.capture2e({ "ARCHIVE" => archive, "PLACE" => place }, *command)
    assert_predicate status, :success?, out
  end

  # Runs the app, never through a shell, with nothing in its environment
  # but +env+. Windows' network and cryptography libraries need
  # SystemRoot, so on Windows that stays, with a PATH of System32.
  def run_app(env, app, *argv)
    if @platform.windows?
      system_root = ENV.fetch("SystemRoot", "C:\\Windows")
      env = { "SystemRoot" => system_root, "PATH" => File.join(system_root, "System32") }.merge(env)
    end
    Open3.capture3(env, [app, app], *argv, unsetenv_others: true, chdir: Dir.tmpdir)
  end
end
