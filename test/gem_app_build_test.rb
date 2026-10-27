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

        notices = File.read(File.join(@dir, folder, "notices/GEMS.txt"))
        assert_includes notices, "native 1.0.0 (#{native.platform})\n  License: BSD-3-Clause\n"
        assert_includes notices, "  From: #{@server.url("/gems/#{native.file_name}")}\n"
        assert_includes notices, "foo 1.0.0: LICENSE.txt\n#{'=' * 72}\n\nfoo is MIT\n"
        refute_includes notices, "csv"

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

  def test_every_gem_that_cannot_ship_is_named_with_what_to_do
    gpl = FakeGem.build(@gems, "copyleft", "1.0.0", licenses: ["GPL-3.0-only"])
    unlabeled = FakeGem.build(@gems, "unlabeled", "1.0.0", licenses: [])
    needs_compiling = FakeGem.build(@gems, "needs_compiling", "1.0.0", extensions: ["ext/needs_compiling/extconf.rb"],
      files: { "ext/needs_compiling/extconf.rb" => "", "LICENSE" => "MIT\n" })
    old = FakeGem.build(@gems, "old", "1.0.0", platform: "x86_64-linux-gnu", required_ruby_version: "< 3.5")
    root = project(dependencies: { "copyleft" => ">= 0", "unlabeled" => ">= 0", "needs_compiling" => ">= 0", "old" => ">= 0" },
      locked: [gpl, unlabeled, needs_compiling, old])

    out, err, status = build("-t", "x86_64-linux", root, host: "aarch64-linux")

    assert_equal [1, ""], [status, out]
    assert_equal [
      "fledge build: MyApp can't ship for x86_64-linux:",
      "fledge build:   copyleft 1.0.0 is GPL-3.0-only, and Fledge ships only gems whose licenses ask nothing beyond keeping " \
        "their notices (doc/licensing.md). If its license is another, give it in fledge.yml, under licenses, such as " \
        "licenses: {copyleft: MIT}.",
      "fledge build:   needs_compiling 1.0.0 has an extension to compile, and the lockfile locks no build of it precompiled for " \
        "x86_64-linux. Fledge compiles a gem only on the platform it is for, and this computer is aarch64-linux: build for " \
        "x86_64-linux on a computer that is x86_64-linux, such as a CI runner of that platform, or choose a version of " \
        "needs_compiling with a build for x86_64-linux and run bundle lock --add-platform x86_64-linux.",
      "fledge build:   old 1.0.0 (x86_64-linux-gnu) needs Ruby < 3.5, and Fledge's runtime is Ruby 4.0.9.",
      "fledge build:   unlabeled 1.0.0 declares no license, and Fledge ships only gems whose licenses ask nothing beyond " \
        "keeping their notices (doc/licensing.md). If its license is another, give it in fledge.yml, under licenses, " \
        "such as licenses: {unlabeled: MIT}.",
    ], err.lines.map(&:chomp).grep_v(/\ADownloading /)
    assert_empty Dir.glob(File.join(@dir, "dist", "*"))
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
    notices = File.read(File.join(@dir, "dist/MyApp-aarch64-linux/notices/GEMS.txt"))
    assert_includes notices, "alpha 1.0\n  License: MIT\n"
    assert_includes notices, "  From: #{repo} at #{revision} (branch trunk)\n"
    assert_includes notices, "lib/ruby/gems/4.0.0/bundler/gems/#{scope}/gems/alpha/LICENSE"
  end

  def test_fledge_yml_gives_the_license_a_gem_does_not_declare
    unlabeled = FakeGem.build(@gems, "unlabeled", "1.0.0", licenses: [], files: { "lib/unlabeled.rb" => "" })
    root = project(dependencies: { "unlabeled" => ">= 0" }, locked: [unlabeled])
    File.write(File.join(root, "fledge.yml"), "licenses:\n  unlabeled: MIT\n")

    _, err, status = build("-t", "x86_64-linux", root)

    assert_equal 0, status, err
    assert_equal "fledge build: warning: unlabeled 1.0.0 ships no license file, so notices/GEMS.txt names its license but " \
      "cannot quote it.\n", err.lines.grep(/warning/).join
    notices = File.read(File.join(@dir, "dist/MyApp-x86_64-linux/notices/GEMS.txt"))
    assert_includes notices, "  License: MIT (as fledge.yml gives it; the gem declares NOASSERTION)\n"
    assert_includes notices, "  License files: none: the gem ships no license text\n"
  end

  # A native gem whose compiled code holds a copyleft library compiled
  # in fails, naming the gem, the file, the library, and why; one whose
  # compiled code no one reviewed fails saying how to declare it; and once
  # fledge.yml declares what it holds, GEMS.txt says so (ADR 005,
  # section 7).
  def test_a_native_gems_compiled_code_is_judged_by_what_it_holds
    iconv = FakeGem.build(@gems, "iconvy", "1.0.0", platform: "x86_64-linux-gnu",
      files: { "lib/iconvy.so" => Binaries.elf(payload: "UCS-4-INTERNAL MULELAO-1"), "LICENSE" => "MIT\n" })
    mystery = FakeGem.build(@gems, "mystery", "1.0.0", platform: "x86_64-linux-gnu",
      files: { "lib/mystery.so" => Binaries.elf(needed: ["libc.so.6"], payload: "libfoo 1.2"), "LICENSE" => "MIT\n" })
    root = project(dependencies: { "iconvy" => ">= 0", "mystery" => ">= 0" }, locked: [iconv, mystery])

    _, err, status = build("-t", "x86_64-linux", root)

    assert_equal 1, status
    problems = err.lines.map(&:chomp).grep_v(/\ADownloading /)
    assert_equal "fledge build: MyApp can't ship for x86_64-linux:", problems.first
    assert_match(%r{\Afledge build:   iconvy 1\.0\.0 \(x86_64-linux-gnu\) compiles GNU libiconv's code \(LGPL-2\.1-or-later\) into lib/iconvy\.so\.},
      problems[1])
    assert_match(%r{\Afledge build:   mystery 1\.0\.0 \(x86_64-linux-gnu\) ships compiled code \(lib/mystery\.so\) that Fledge has not reviewed},
      problems[2])
  end

  def test_fledge_yml_says_what_a_native_gems_compiled_code_holds
    mystery = FakeGem.build(@gems, "mystery", "1.0.0", platform: "x86_64-linux-gnu",
      files: { "lib/mystery.so" => Binaries.elf(needed: ["libc.so.6"], payload: "libfoo 1.2"), "LICENSE" => "MIT\n" })
    root = project(dependencies: { "mystery" => ">= 0" }, locked: [mystery])
    File.write(File.join(root, "fledge.yml"), "compiled:\n  mystery:\n    - {name: libfoo 1.2, license: BSD-3-Clause}\n")

    _, err, status = build("-t", "x86_64-linux", root)

    assert_equal 0, status, err
    notices = File.read(File.join(@dir, "dist/MyApp-x86_64-linux/notices/GEMS.txt"))
    assert_includes notices, "mystery 1.0.0 (x86_64-linux-gnu)\n  License: MIT\n"
    assert_includes notices, "  Compiled in: libfoo 1.2 (BSD-3-Clause, as fledge.yml gives it), in lib/mystery.so\n"
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
