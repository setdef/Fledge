# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/git_repos"
require "stringio"

# A git gem fetched at the revision its lockfile locks, and laid out as
# Bundler lays out a git gem's checkout, from real git repositories.
class GitCheckoutTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @repo, @revision = FakeRepo.write(@dir, "Monorepo", gems: {
      "alpha" => { "lib/alpha.rb" => "# alpha\n", "LICENSE.txt" => "alpha is MIT\n", "LICENSES/MIT.txt" => "MIT text\n" },
      "beta" => { "lib/beta.rb" => "# beta\n" },
    })
    @log = StringIO.new
    @checkouts = Fledge::GitCheckout.new(cache: File.join(@dir, "cache"), work: File.join(@dir, "work"), log: @log)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def gem(name = "alpha", revision: @revision, version: "1.0")
    Fledge::GitGem.new(name:, version:, uri: @repo, revision:, glob: "gems/*/*.gemspec", ref: "branch trunk", submodules: false)
  end

  def test_checks_out_the_locked_revision_with_its_gemspecs_evaluated_as_bundler_does
    FakeRepo.git(@repo, "-c", "user.name=Fledge", "-c", "user.email=fledge@example.com", "commit", "--quiet", "--allow-empty", "-m", "Later")
    folder = @checkouts.checkout(gem)

    assert_equal @revision, FakeRepo.git(folder, "rev-parse", "HEAD").strip

    assert_equal "# alpha\n", File.read(File.join(folder, "gems/alpha/lib/alpha.rb"))
    gemspec = File.read(File.join(folder, "gems/beta/beta.gemspec"))
    refute_includes gemspec, "git ls-files", "a built app has no git to evaluate a gemspec with"
    assert_includes gemspec, "s.files = [\"beta.gemspec\".freeze, \"lib/beta.rb\".freeze]"
    assert_equal folder, @checkouts.checkout(gem("beta")), "one checkout serves every gem of a repository's revision"
    assert_includes @log.string, "Fetching #{@repo}"
  end

  def test_a_revision_the_repository_does_not_hold_is_refused
    error = assert_raises(Fledge::Error) { @checkouts.checkout(gem(revision: "b" * 40)) }

    assert_equal "#{@repo} holds no commit #{'b' * 40}, which the lockfile locks for alpha 1.0. Run bundle lock, then build again.",
      error.message
  end

  # A repository holds more than its gems (Ferro's holds its tooling,
  # under another license, and symbolic links a Windows .zip cannot
  # hold), so a gem ships its own folder of the checkout, where Bundler
  # keeps it.
  def test_the_package_ships_its_own_folder_of_the_checkout_where_bundler_keeps_it
    File.write(File.join(@repo, "TOOLING.md"), "the repository's own\n")
    FakeRepo.git(@repo, "add", ".")
    FakeRepo.git(@repo, "-c", "user.name=Fledge", "-c", "user.email=fledge@example.com", "commit", "--quiet", "-m", "Tooling")
    revision = FakeRepo.git(@repo, "rev-parse", "HEAD").strip
    alpha = gem(revision:)
    package = Fledge::GitPackage.new(alpha, @checkouts.checkout(alpha))

    paths = package.entries("lib/ruby/gems/4.0.0").map(&:path)
    scope = "lib/ruby/gems/4.0.0/bundler/gems/#{alpha.scope}"
    assert_includes paths, "#{scope}/gems/alpha/lib/alpha.rb"
    assert_includes paths, "#{scope}/gems/alpha/alpha.gemspec"
    refute_includes paths, "#{scope}/gems/beta/beta.gemspec", "another gem of the repository ships only if the app locks it"
    refute_includes paths, "#{scope}/TOOLING.md", "the repository's own files are not the gem's"
    assert paths.none? { |path| path.include?("/.git") }, "git's own files stay behind"
    assert_equal "#{scope}/gems/alpha", package.installed_path("lib/ruby/gems/4.0.0")
    refute_empty Dir.glob(File.join(package.checkout, "gems/beta/*")), "the checkout itself is whole"
    assert_equal ["alpha", "1.0"], [package.spec.name, package.spec.version.to_s]
    assert_equal ["LICENSE.txt", "LICENSES/MIT.txt", "alpha.gemspec", "lib/alpha.rb"], package.contents.keys.sort
    assert_empty package.problems(ruby_version: "4.0.9")
    refute_predicate package, :extensions?
  end

  def test_a_gemspec_of_another_version_than_the_lockfiles_is_refused
    error = assert_raises(Fledge::Error) { Fledge::GitPackage.new(gem(version: "2.0"), @checkouts.checkout(gem)) }

    assert_equal "#{@repo} at #{@revision} holds alpha 1.0, but the lockfile locks alpha 2.0. Run bundle lock, then build again.",
      error.message
  end

  # Bundler's GitProxy#copy_to runs `git submodule update --init
  # --recursive` for a source with submodules: true, and takes the
  # submodules out otherwise. git blocks the file transport for submodules
  # by default, which only a test's local repositories need allowed.
  def test_a_gem_that_asks_for_its_submodules_gets_them_at_the_commit_the_repository_locks
    sub, = FakeRepo.write(@dir, "Sub", gems: { "inner" => { "lib/inner.rb" => "# inner\n" } })
    identity = ["-c", "user.name=Fledge", "-c", "user.email=fledge@example.com"]
    FakeRepo.git(@repo, "-c", "protocol.file.allow=always", "submodule", "add", "--quiet", sub, "vendor/sub")
    FakeRepo.git(@repo, *identity, "commit", "--quiet", "-m", "A submodule")
    revision = FakeRepo.git(@repo, "rev-parse", "HEAD").strip
    allowed = ENV.values_at("GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0")
    ENV.update("GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "protocol.file.allow", "GIT_CONFIG_VALUE_0" => "always")

    with = gem(revision:).with(submodules: true)
    folder = @checkouts.checkout(with)
    assert_equal "# inner\n", File.read(File.join(folder, "vendor/sub/gems/inner/lib/inner.rb"))
    package = Fledge::GitPackage.new(with, folder)
    assert package.entries("g").none? { |entry| entry.path.end_with?("/.git") }, "a submodule's own .git file stays behind"

    without = Fledge::GitCheckout.new(cache: File.join(@dir, "cache"), work: File.join(@dir, "work2"), log: @log).checkout(gem(revision:))
    assert_empty Dir.children(File.join(without, "vendor/sub")), "without submodules: true the submodule's folder is empty, as Bundler leaves it"
  ensure
    %w[GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0].zip(allowed.to_a).each { |key, value| ENV[key] = value }
  end
end
