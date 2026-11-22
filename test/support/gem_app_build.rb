# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "gems"
require_relative "loopback_server"
require "stringio"

# fledge build for a gem-shaped app, through real streams: real
# .gem files, built by RubyGems, served by a real HTTP server at the
# lockfile's remote, into fake runtimes. test/gem_app_build_test.rb
# builds for Linux, and test/integration/gem_app_windows_build_test.rb
# for Windows on Windows, with the real Windows runtime's launchers.
module GemAppBuild
  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, ".git"))
    @runtimes = File.join(@dir, "runtimes")
    FileUtils.mkdir_p(@runtimes)
    Fledge::Platform.names.each { |name| FakeRuntime.write(@runtimes, Fledge::Platform.find(name)) }
    @gems = File.join(@dir, "gems")
    FileUtils.mkdir_p(@gems)
    @routes = {}
    @server = LoopbackServer.new(@routes)
  end

  def teardown
    @server.stop
    FileUtils.rm_rf(@dir)
  end

  def serve(*gems)
    gems.each { |gem| @routes["/gems/#{gem.file_name}"] = [200, {}, File.binread(gem.path)] }
  end

  def project(dependencies:, locked:, **)
    serve(*locked)
    FakeProject.write(@dir, dependencies:, locked:, remote: @server.url("/"), **)
  end

  def build(*argv, host: "x86_64-linux")
    out = StringIO.new
    err = StringIO.new
    env = { "FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache") }
    status = Dir.chdir(@dir) { Fledge::CLI::Build.new(out:, err:, env:, host: Gem::Platform.new(host), pins: FakeRuntime.pins(@runtimes)).call(argv) }
    [out.string, err.string, status]
  end

  # A project that locks foo, which needs bar and has a RubyGems plugin,
  # a native gem for Linux and for Windows, and csv, which the runtime
  # has already; and the two native gems.
  def locked_gems_project
    bar = FakeGem.build(@gems, "bar", "2.0.0")
    foo = FakeGem.build(@gems, "foo", "1.0.0", dependencies: { "bar" => ">= 0" }, plugin: true)
    linux = FakeGem.build(@gems, "native", "1.0.0", platform: "x86_64-linux-gnu", licenses: ["BSD-3-Clause"])
    windows = FakeGem.build(@gems, "native", "1.0.0", platform: "x64-mingw-ucrt", licenses: ["BSD-3-Clause"])
    csv = FakeGem.build(@gems, "csv", "3.3.5", licenses: %w[Ruby BSD-2-Clause])
    root = project(dependencies: { "foo" => "~> 1.0", "native" => ">= 0", "csv" => ">= 0" },
      locked: [bar, foo, linux, windows, csv], locked_dependencies: { foo.lock_name => ["bar (>= 0)"] })

    [root, linux, windows]
  end

  # The locked gems of locked_gems_project ship in the app +folder+,
  # in its gem folder +gem_dir+, with the +native+ gem for its platform.
  def assert_the_locked_gems_ship(folder, gem_dir, native)
    gems = File.join(@dir, folder, gem_dir)
    assert_equal "# foo\n", File.read(File.join(gems, "gems/foo-1.0.0/lib/foo.rb"))
    assert_path_exists File.join(gems, "gems/bar-2.0.0/lib/bar.rb")
    assert_path_exists File.join(gems, "gems/native-1.0.0-#{native.platform}/lib/native.rb")
    assert_equal File.binread(native.path), File.binread(File.join(gems, "cache/native-1.0.0-#{native.platform}.gem"))
    spec = Gem::Specification.load(File.join(gems, "specifications/foo-1.0.0.gemspec"))
    assert_equal ["foo", "1.0.0", ["bar"]], [spec.name, spec.version.to_s, spec.dependencies.map(&:name)]
    assert_equal "require_relative '../gems/foo-1.0.0/lib/rubygems_plugin.rb'\n", File.read(File.join(gems, "plugins/foo_plugin.rb"))
    refute_path_exists File.join(gems, "gems/csv-3.3.5"), "the runtime's own csv 3.3.5 stays the runtime's"

    assert_equal "foo is MIT\n", File.read(File.join(gems, "gems/foo-1.0.0/LICENSE.txt")), "a gem's own notices ship in its folder"
    refute_path_exists File.join(@dir, folder, "notices/GEMS.txt"), "Fledge writes no notices of its own for the app's gems"

    assert_equal "#{Fledge::Bundle::SETTINGS}BUNDLE_WITHOUT: \"\"\nBUNDLE_WITH: \"\"\n", File.read(File.join(@dir, folder, "app/.bundle/config"))
    gemspec = File.read(File.join(@dir, folder, "app/my_app.gemspec"))
    refute_includes gemspec, "git ls-files", "the gemspec ships evaluated, so it needs no git"
    assert_includes gemspec, "s.name = \"my_app\""
  end
end
