# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/binaries"
require_relative "../support/gems"
require_relative "../support/git_repos"
require_relative "../support/loopback_server"
require "stringio"

# fledge build for a gem-shaped app whose lockfile locks a gem from a
# git repository, through real streams, into fake runtimes:
# git itself makes the repository and checks it out.
# test/gem_app_build_test.rb covers gems from a gem server.
class GitGemBuildTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, ".git"))
    @runtimes = File.join(@dir, "runtimes")
    FileUtils.mkdir_p(@runtimes)
    Fledge::Platform.names.each { |name| FakeRuntime.write(@runtimes, Fledge::Platform.find(name)) }
    @server = LoopbackServer.new({})
  end

  def teardown
    @server.stop
    FileUtils.rm_rf(@dir)
  end

  def build(*argv, host: "x86_64-linux")
    out = StringIO.new
    err = StringIO.new
    env = { "FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache") }
    status = Dir.chdir(@dir) { Fledge::CLI::Build.new(out:, err:, env:, host: Gem::Platform.new(host)).call(argv) }
    [out.string, err.string, status]
  end

  # A git gem ships as Bundler keeps one, for every platform, when it has
  # nothing to compile.
  def test_a_git_gem_ships_where_bundler_keeps_it_for_every_platform
    repo, revision = FakeRepo.write(@dir, "Monorepo", gems: { "alpha" => { "lib/alpha.rb" => "# alpha\n", "LICENSE" => "MIT\n" } })
    root = git_project(repo, revision)

    _, err, status = build(root, host: "aarch64-linux")
    assert_equal 0, status, err

    scope = "Monorepo-#{revision[0, 12]}"
    if FakeRuntime.windows
      _, err, status = build(root, host: "x64-mingw-ucrt")
      assert_equal 0, status, err
      assert_equal "# alpha\n", File.read(File.join(@dir, "dist/MyApp-x64-mingw-ucrt/ruby/lib/ruby/gems/4.1.0+5/bundler/gems", scope,
        "gems/alpha/lib/alpha.rb"))
    end
    gemspec = File.read(File.join(@dir, "dist/MyApp-aarch64-linux/lib/ruby/gems/4.1.0+5/bundler/gems", scope, "gems/alpha/alpha.gemspec"))
    refute_includes gemspec, "git ls-files"
    assert_equal "MIT\n", File.read(File.join(@dir, "dist/MyApp-aarch64-linux/lib/ruby/gems/4.1.0+5/bundler/gems", scope, "gems/alpha/LICENSE"))
  end

  # The linkage check reads what a git gem holds as a gem: the files its
  # gemspec lists, and those under its require paths. A test's compiled
  # fixture elsewhere in the checkout, which no install of the gem holds,
  # ships, as bundle exec has it, and is not judged, as Fledge's own
  # test/fixtures/binaries were judged; a file under lib/ is.
  def test_a_git_gems_compiled_test_fixture_ships_unjudged
    TestReaders.need(self, :elf)
    fixture = Binaries.elf(needed: %w[libc.so.6 libxml2.so.2])
    files = { "lib/alpha.rb" => "# alpha\n", "test/fixtures/broken.so" => fixture }
    repo, revision = FakeRepo.write(@dir, "Monorepo", gems: { "alpha" => files })
    root = git_project(repo, revision)

    _, err, status = build(root)

    assert_equal 0, status, err
    shipped = File.join(@dir, "dist/MyApp-x86_64-linux/lib/ruby/gems/4.1.0+5/bundler/gems", "Monorepo-#{revision[0, 12]}",
      "gems/alpha/test/fixtures/broken.so")
    assert_equal fixture, File.binread(shipped)

    FileUtils.rm_rf([File.join(@dir, "Monorepo"), File.join(@dir, "dist"), File.join(@dir, "cache"), root])
    repo, revision = FakeRepo.write(@dir, "Monorepo", gems: { "alpha" => files.merge("lib/alpha/broken.so" => fixture) })
    _, err, status = build(git_project(repo, revision))

    assert_equal 1, status
    assert_includes err, "lib/alpha/broken.so needs libxml2.so.2"
  end

  # A project whose Gemfile takes alpha from the git repository +repo+ at
  # +revision+.
  def git_project(repo, revision)
    root = FakeProject.write(@dir, dependencies: {}, locked: [], remote: @server.url("/"),
      gemfile: "gem \"alpha\", git: #{repo.inspect}, branch: \"trunk\", glob: \"gems/*/*.gemspec\"\n", lock_dependencies: ["alpha!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  alpha (1.0)\n")
    File.write(lock, "GIT\n  remote: #{repo}\n  revision: #{revision}\n  branch: trunk\n  glob: gems/*/*.gemspec\n  specs:\n" \
      "    alpha (1.0)\n\n#{text}")
    root
  end
end
