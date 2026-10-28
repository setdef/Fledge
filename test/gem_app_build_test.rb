# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"
require_relative "support/gems"
require_relative "support/loopback_server"
require "stringio"

# fledge build for a gem-shaped app (ADR 005), through real streams: real
# .gem files, built by RubyGems, served by a real HTTP server at the
# lockfile's remote, into fake runtimes.
class GemAppBuildTest < Minitest::Test
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
    status = Dir.chdir(@dir) { Fledge::CLI::Build.new(out:, err:, env:, host: Gem::Platform.new(host)).call(argv) }
    [out.string, err.string, status]
  end

  def test_the_locked_gems_ship_for_each_platform_beside_the_runtimes_own
    bar = FakeGem.build(@gems, "bar", "2.0.0")
    foo = FakeGem.build(@gems, "foo", "1.0.0", dependencies: { "bar" => ">= 0" }, plugin: true)
    linux = FakeGem.build(@gems, "native", "1.0.0", platform: "x86_64-linux-gnu", licenses: ["BSD-3-Clause"])
    windows = FakeGem.build(@gems, "native", "1.0.0", platform: "x64-mingw-ucrt", licenses: ["BSD-3-Clause"])
    csv = FakeGem.build(@gems, "csv", "3.3.5", licenses: %w[Ruby BSD-2-Clause])
    root = project(dependencies: { "foo" => "~> 1.0", "native" => ">= 0", "csv" => ">= 0" },
      locked: [bar, foo, linux, windows, csv], locked_dependencies: { foo.lock_name => ["bar (>= 0)"] })

    out, err, status = build("-t", "x86_64-linux", "-t", "x64-mingw-ucrt", File.join(root, "exe/my_app"))

    assert_equal 0, status, err
    assert_equal "dist/MyApp-x86_64-linux.tar.gz\ndist/MyApp-x64-mingw-ucrt.zip\n", out
    { "dist/MyApp-x86_64-linux" => ["lib/ruby/gems/4.0.0", linux], "dist/MyApp-x64-mingw-ucrt" => ["ruby/lib/ruby/gems/4.0.0", windows] }
      .each do |folder, (gem_dir, native)|
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

        assert_equal Fledge::Bundle::SETTINGS, File.read(File.join(@dir, folder, "app/.bundle/config"))
        gemspec = File.read(File.join(@dir, folder, "app/my_app.gemspec"))
        refute_includes gemspec, "git ls-files", "the gemspec ships evaluated, so it needs no git"
        assert_includes gemspec, "s.name = \"my_app\""
      end
    assert_equal 1, err.scan("Downloading native-1.0.0-x86_64-linux-gnu.gem from #{@server.url('/')}").size
    assert_equal 1, @server.requests.count("/gems/foo-1.0.0.gem"), "a gem downloaded once is taken from the cache"
  end

  def test_a_gem_the_lockfile_does_not_lock_for_the_platform_says_what_to_run
    native = FakeGem.build(@gems, "native", "1.0.0", platform: "x86_64-linux-gnu")
    root = project(dependencies: { "native" => ">= 0" }, locked: [native], platforms: %w[x86_64-linux arm64-darwin])

    _, err, status = build("-t", "x64-mingw-ucrt", "-t", "arm64-darwin", root)

    assert_equal 1, status
    assert_equal "fledge build: Gemfile.lock locks no gems for x64-mingw-ucrt. Run bundle lock --add-platform x64-mingw-ucrt, " \
      "then build again.\n", err
    _, err, = build("-t", "arm64-darwin", root)
    assert_equal "fledge build: Gemfile.lock locks no build of native for arm64-darwin, only for x86_64-linux-gnu. " \
      "If native has one, run bundle lock --add-platform arm64-darwin, then build again.\n", err
    refute_path_exists File.join(@dir, "dist/MyApp-arm64-darwin")
  end

  # Fledge refuses a gem only when it would not run where the app goes,
  # and names every such gem at once.
  def test_every_gem_that_would_not_run_is_named_with_what_to_do
    needs_compiling = FakeGem.build(@gems, "needs_compiling", "1.0.0", extensions: ["ext/needs_compiling/extconf.rb"],
      files: { "ext/needs_compiling/extconf.rb" => "", "LICENSE" => "MIT\n" })
    old = FakeGem.build(@gems, "old", "1.0.0", platform: "x86_64-linux-gnu", required_ruby_version: "< 3.5")
    unloadable = FakeGem.build(@gems, "unloadable", "1.0.0", platform: "x86_64-linux-gnu",
      files: { "lib/unloadable.so" => Binaries.elf(needed: %w[libc.so.6 libxml2.so.2]) })
    root = project(dependencies: { "needs_compiling" => ">= 0", "old" => ">= 0", "unloadable" => ">= 0" },
      locked: [needs_compiling, old, unloadable])

    out, err, status = build("-t", "x86_64-linux", root, host: "aarch64-linux")

    assert_equal [1, ""], [status, out]
    assert_equal [
      "fledge build: MyApp can't ship for x86_64-linux:",
      "fledge build:   needs_compiling 1.0.0 has an extension to compile, and the lockfile locks no build of it precompiled for " \
        "x86_64-linux. Fledge compiles a gem only on the platform it is for, and this computer is aarch64-linux: build for " \
        "x86_64-linux on a computer that is x86_64-linux, such as a CI runner of that platform, or choose a version of " \
        "needs_compiling with a build for x86_64-linux and run bundle lock --add-platform x86_64-linux.",
      "fledge build:   old 1.0.0 (x86_64-linux-gnu) needs Ruby < 3.5, and Fledge's runtime is Ruby 4.0.9.",
      "fledge build:   unloadable 1.0.0 (x86_64-linux-gnu)'s lib/unloadable.so needs libxml2.so.2, which neither linux, nor " \
        "Fledge's runtime, nor the gem itself provides, so the app could not load it on another computer. Build the gem so " \
        "that it carries the library, or links it statically.",
    ], err.lines.map(&:chomp).grep_v(/\ADownloading /)
    assert_empty Dir.glob(File.join(@dir, "dist", "*"))
  end

  # The gems an app depends on, and their licenses, are its developer's
  # choice and responsibility, not Fledge's (the maintainer's words of
  # 2026-10-28; ADR 007). So every one of these ships: a GPL gem, an
  # AGPL native gem shaped like Tokra, a gem that declares no license, a
  # precompiled LGPL gem whose source the lockfile does not pin, an MPL
  # gem, one that names a license SPDX does not know, and a native gem
  # with GNU libiconv's code compiled into it, as nokogiri's precompiled
  # macOS and Windows builds have, that no one has reviewed.
  def test_a_gem_ships_whatever_its_license_and_whatever_its_compiled_files_hold
    gems = [
      FakeGem.build(@gems, "copyleft", "1.0.0", licenses: ["GPL-3.0-only"]),
      FakeGem.build(@gems, "tokraish", "1.0.0", platform: "x86_64-linux-gnu", licenses: ["AGPL-3.0-or-later"],
        files: { "lib/tokraish/tokraish.so" => Binaries.elf(needed: ["libc.so.6"]), "LICENSE" => "AGPL-3.0-or-later\n" }),
      FakeGem.build(@gems, "unlabeled", "1.0.0", licenses: [], files: { "lib/unlabeled.rb" => "" }),
      FakeGem.build(@gems, "binder", "2.0.0", platform: "x86_64-linux", licenses: ["LGPL-2.1-or-later"]),
      FakeGem.build(@gems, "mozilla", "1.0.0", licenses: ["MPL-2.0"]),
      FakeGem.build(@gems, "unknown", "1.0.0", licenses: ["GPL-3.0", "My Own License"]),
      FakeGem.build(@gems, "iconvy", "1.0.0", platform: "x86_64-linux-gnu",
        files: { "lib/iconvy.so" => Binaries.elf(needed: ["libc.so.6"], payload: "UCS-4-INTERNAL MULELAO-1"), "LICENSE" => "MIT\n" }),
    ]
    root = project(dependencies: gems.to_h { |gem| [gem.name, ">= 0"] }, locked: gems)

    _, err, status = build("-t", "x86_64-linux", root)

    assert_equal 0, status, err
    assert_empty err.lines.grep_v(/\ADownloading /), "no warnings, and no verdicts"
    installed = File.join(@dir, "dist/MyApp-x86_64-linux/lib/ruby/gems/4.0.0")
    gems.each { |gem| assert_path_exists File.join(installed, "specifications", "#{File.basename(gem.file_name, '.gem')}.gemspec"), gem.name }
    assert_path_exists File.join(installed, "gems/tokraish-1.0.0-x86_64-linux-gnu/lib/tokraish/tokraish.so")
    assert_path_exists File.join(installed, "gems/iconvy-1.0.0-x86_64-linux-gnu/lib/iconvy.so")
    refute_path_exists File.join(@dir, "dist/MyApp-x86_64-linux/notices/GEMS.txt")
  end

  # fledge.yml no longer says what a gem's license is or what its
  # compiled files hold, since Fledge no longer asks; like any key it does
  # not know, each fails the build, so a stale file is noticed.
  def test_fledge_yml_keys_that_judged_gems_are_unknown
    root = project(dependencies: {}, locked: [])
    { "licenses:\n  unlabeled: MIT\n" => "'licenses'", "compiled:\n  mystery: []\n" => "'compiled'" }.each do |yaml, key|
      File.write(File.join(root, "fledge.yml"), yaml)

      _, err, status = build("-t", "x86_64-linux", root)

      assert_equal 1, status
      assert_equal "fledge build: #{File.join(root, 'fledge.yml')} has #{key}, which Fledge does not know. It knows #{Fledge::Config::KNOWN}.\n", err
    end
  end

  # On a computer Fledge has no runtime for, nothing compiles.
  def test_a_gem_with_an_extension_is_refused_on_a_computer_fledge_has_no_runtime_for
    needs_compiling = FakeGem.build(@gems, "needs_compiling", "1.0.0", extensions: ["ext/needs_compiling/extconf.rb"],
      files: { "ext/needs_compiling/extconf.rb" => "", "LICENSE" => "MIT\n" })
    root = project(dependencies: { "needs_compiling" => ">= 0" }, locked: [needs_compiling])

    _, err, status = build("-t", "x86_64-linux", root, host: "x86_64-freebsd")

    assert_equal 1, status
    assert_includes err, "Fledge compiles a gem only on the platform it is for, and Fledge has no runtime for this computer: build"
  end

  # A git gem ships as Bundler keeps one, for every platform, from any
  # computer, when it has nothing to compile (ADR 006).
  def test_a_git_gem_ships_where_bundler_keeps_it_for_every_platform
    require_relative "support/git_repos"
    repo, revision = FakeRepo.write(@dir, "Monorepo", gems: { "alpha" => { "lib/alpha.rb" => "# alpha\n", "LICENSE" => "MIT\n" } })
    root = FakeProject.write(@dir, dependencies: {}, locked: [], remote: @server.url("/"),
      gemfile: "gem \"alpha\", git: #{repo.inspect}, branch: \"trunk\", glob: \"gems/*/*.gemspec\"\n", lock_dependencies: ["alpha!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  alpha (1.0)\n")
    File.write(lock, "GIT\n  remote: #{repo}\n  revision: #{revision}\n  branch: trunk\n  glob: gems/*/*.gemspec\n  specs:\n" \
      "    alpha (1.0)\n\n#{text}")

    _, err, status = build("-t", "x64-mingw-ucrt", "-t", "aarch64-linux", root)

    assert_equal 0, status, err
    scope = "Monorepo-#{revision[0, 12]}"
    assert_equal "# alpha\n", File.read(File.join(@dir, "dist/MyApp-x64-mingw-ucrt/ruby/lib/ruby/gems/4.0.0/bundler/gems", scope,
      "gems/alpha/lib/alpha.rb"))
    gemspec = File.read(File.join(@dir, "dist/MyApp-aarch64-linux/lib/ruby/gems/4.0.0/bundler/gems", scope, "gems/alpha/alpha.gemspec"))
    refute_includes gemspec, "git ls-files"
    assert_equal "MIT\n", File.read(File.join(@dir, "dist/MyApp-aarch64-linux/lib/ruby/gems/4.0.0/bundler/gems", scope, "gems/alpha/LICENSE"))
  end

  def test_a_gem_whose_file_differs_from_the_lockfile_is_refused
    foo = FakeGem.build(@gems, "foo", "1.0.0")
    root = project(dependencies: { "foo" => ">= 0" }, locked: [foo])
    @routes["/gems/foo-1.0.0.gem"] = [200, {}, "not the gem"]

    _, err, status = build("-t", "x86_64-linux", root)

    assert_equal 1, status
    assert_match(/\Afledge build: .*foo-1\.0\.0\.gem.*SHA-256/, err.lines.grep(/SHA-256/).first.to_s)
  end
end
