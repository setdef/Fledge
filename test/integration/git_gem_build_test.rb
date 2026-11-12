# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/gems"
require_relative "../support/git_repos"
require_relative "../support/loopback_server"
require "stringio"

# fledge build for a gem-shaped app whose lockfile locks a gem from a
# git repository (ADR 006), through real streams, into fake runtimes:
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
  # nothing to compile (ADR 006).
  def test_a_git_gem_ships_where_bundler_keeps_it_for_every_platform
    repo, revision = FakeRepo.write(@dir, "Monorepo", gems: { "alpha" => { "lib/alpha.rb" => "# alpha\n", "LICENSE" => "MIT\n" } })
    root = FakeProject.write(@dir, dependencies: {}, locked: [], remote: @server.url("/"),
      gemfile: "gem \"alpha\", git: #{repo.inspect}, branch: \"trunk\", glob: \"gems/*/*.gemspec\"\n", lock_dependencies: ["alpha!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  alpha (1.0)\n")
    File.write(lock, "GIT\n  remote: #{repo}\n  revision: #{revision}\n  branch: trunk\n  glob: gems/*/*.gemspec\n  specs:\n" \
      "    alpha (1.0)\n\n#{text}")

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
end
