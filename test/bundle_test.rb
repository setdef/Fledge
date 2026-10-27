# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/gems"

# Fledge::Bundle reads a Gemfile and lockfile with Bundler and picks, for
# each platform, the gems Bundler would set up there.
class BundleTest < Minitest::Test
  LINUX = Fledge::Platform.find("x86_64-linux")
  WINDOWS = Fledge::Platform.find("x64-mingw-ucrt")
  DARWIN = Fledge::Platform.find("arm64-darwin")

  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, ".git"))
    @bar = FakeGem.build(@dir, "bar", "2.0.0")
    @foo = FakeGem.build(@dir, "foo", "1.0.0")
    @linux = FakeGem.build(@dir, "native", "1.0.0", platform: "x86_64-linux-gnu")
    @musl = FakeGem.build(@dir, "native", "1.0.0", platform: "x86_64-linux-musl")
    @windows = FakeGem.build(@dir, "native", "1.0.0", platform: "x64-mingw-ucrt")
    @darwin = FakeGem.build(@dir, "native", "1.0.0", platform: "arm64-darwin")
    @source = FakeGem.build(@dir, "native", "1.0.0")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def bundle(**)
    root = FakeProject.write(@dir, **)
    Fledge::Bundle.new(Fledge::App.at(root))
  end

  def names(bundle, platform) = bundle.gems_for(platform, ruby_version: "4.0.9").map(&:to_s)

  def test_picks_the_build_bundler_would_pick_on_each_platform_and_follows_dependencies
    bundle = bundle(dependencies: { "foo" => ">= 0", "native" => ">= 0" },
      locked: [@bar, @foo, @linux, @musl, @windows, @darwin, @source],
      locked_dependencies: { @foo.lock_name => ["bar (>= 0)"] })

    assert_equal ["bar 2.0.0", "foo 1.0.0", "native 1.0.0 (x86_64-linux-gnu)"], names(bundle, LINUX)
    assert_equal ["bar 2.0.0", "foo 1.0.0", "native 1.0.0 (x64-mingw-ucrt)"], names(bundle, WINDOWS)
    assert_equal ["bar 2.0.0", "foo 1.0.0", "native 1.0.0 (arm64-darwin)"], names(bundle, DARWIN)
    gem = bundle.gems_for(LINUX, ruby_version: "4.0.9").last
    assert_equal ["https://rubygems.org/", @linux.sha256], [gem.remote, gem.sha256]
  end

  def test_falls_back_to_the_build_for_every_platform
    bundle = bundle(dependencies: { "native" => ">= 0" }, locked: [@linux, @source])

    assert_equal ["native 1.0.0"], names(bundle, WINDOWS)
  end

  def test_leaves_out_development_and_test_gems_and_gems_for_other_platforms
    bundle = bundle(dependencies: { "foo" => ">= 0" }, locked: [@foo, @bar, @windows],
      gemfile: "group :development, :test do\n  gem \"bar\"\nend\ngem \"native\", platforms: :windows\n",
      lock_dependencies: ["bar", "native"])

    assert_equal ["foo 1.0.0"], names(bundle, LINUX)
    assert_equal ["foo 1.0.0", "native 1.0.0 (x64-mingw-ucrt)"], names(bundle, WINDOWS)
  end

  def test_a_gem_limited_to_a_ruby_version_follows_the_runtimes
    bundle = bundle(dependencies: {}, locked: [@foo, @bar],
      gemfile: "gem \"foo\", platforms: :mri_40\ngem \"bar\", platforms: :ruby_33\n", lock_dependencies: %w[bar foo])

    assert_equal ["foo 1.0.0"], names(bundle, LINUX)
    assert_empty names(bundle, WINDOWS)
  end

  def test_a_platform_the_lockfile_does_not_lock_is_refused
    bundle = bundle(dependencies: {}, locked: [], platforms: %w[arm64-darwin-25 x86_64-linux-gnu])

    assert_empty names(bundle, LINUX)
    error = assert_raises(Fledge::Error) { names(bundle, DARWIN) }
    assert_equal "Gemfile.lock locks no gems for arm64-darwin. Run bundle lock --add-platform arm64-darwin, then build again.",
      error.message
  end

  def test_a_gem_without_a_checksum_is_refused
    bundle = bundle(dependencies: { "foo" => ">= 0" }, locked: [@foo], checksums: false)

    error = assert_raises(Fledge::Error) { names(bundle, LINUX) }
    assert_equal "Gemfile.lock has no checksum for foo (1.0.0), which x86_64-linux needs, and Fledge checks every gem it " \
      "ships. Run bundle lock --add-checksums, then build again.", error.message
  end

  def test_a_gemfile_asking_for_another_ruby_is_refused
    root = FakeProject.write(@dir, dependencies: {}, locked: [], gemfile: "ruby \"~> 3.3.0\"\n")
    lock = File.join(root, "Gemfile.lock")
    File.write(lock, File.read(lock).sub("BUNDLED WITH", "RUBY VERSION\n  ruby 3.3.6\n\nBUNDLED WITH"))
    bundle = Fledge::Bundle.new(Fledge::App.at(root))

    error = assert_raises(Fledge::Error) { names(bundle, LINUX) }
    assert_equal "Gemfile asks for Ruby ~> 3.3.0, and Fledge's runtimes are Ruby 4.0.9.", error.message
  end

  def test_a_lockfile_the_gemfile_has_moved_past_is_refused_in_bundlers_words
    root = FakeProject.write(@dir, dependencies: {}, locked: [], gemfile: "gem \"foo\"\n")

    error = assert_raises(Fledge::Error) { Fledge::Bundle.new(Fledge::App.at(root)) }
    assert_match(/\ABundler can't read #{Regexp.escape(File.join(root, 'Gemfile'))} and Gemfile.lock:\n/, error.message)
    assert_includes error.message, "* foo"
  end

  def test_a_gemfile_without_a_lockfile_says_to_lock_it
    root = FakeProject.write(@dir, dependencies: {}, locked: [])
    File.delete(File.join(root, "Gemfile.lock"))

    error = assert_raises(Fledge::Error) { Fledge::Bundle.new(Fledge::App.at(root)) }
    assert_equal "#{root} has Gemfile but no Gemfile.lock. Run bundle lock, then build again.", error.message
  end

  def test_a_gem_from_a_folder_outside_the_project_is_refused
    FileUtils.mkdir_p(File.join(@dir, "elsewhere"))
    File.write(File.join(@dir, "elsewhere", "elsewhere.gemspec"),
      "Gem::Specification.new { |s| s.name = 'elsewhere'; s.version = '1.0'; s.summary = 'x'; s.authors = ['x'] }\n")
    root = FakeProject.write(@dir, dependencies: {}, locked: [], gemfile: "gem \"elsewhere\", path: \"../elsewhere\"\n",
      lock_dependencies: ["elsewhere!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  elsewhere (1.0)\n")
    File.write(lock, "PATH\n  remote: ../elsewhere\n  specs:\n    elsewhere (1.0)\n\n#{text}")

    error = assert_raises(Fledge::Error) { names(Fledge::Bundle.new(Fledge::App.at(root)), LINUX) }
    assert_equal "Gemfile.lock takes elsewhere from #{File.join(@dir, 'elsewhere')}, outside the project, and Fledge ships only " \
      "what is inside #{root}. Move it into the project, or take it from a gem server.", error.message
  end

  def test_a_gem_from_git_is_refused
    root = FakeProject.write(@dir, dependencies: {}, locked: [], gemfile: "gem \"g\", git: \"https://example.com/g.git\"\n",
      lock_dependencies: ["g!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  g (1.0)\n")
    File.write(lock, "GIT\n  remote: https://example.com/g.git\n  revision: #{'0' * 40}\n  specs:\n    g (1.0)\n\n#{text}")

    error = assert_raises(Fledge::Error) { names(Fledge::Bundle.new(Fledge::App.at(root)), LINUX) }
    assert_match(%r{\AGemfile.lock takes g from https://example.com/g.git.*, and Fledge ships only gems from a gem server or from folders inside the project\.},
      error.message)
  end

  def test_the_app_folder_gets_bundlers_settings_and_evaluated_gemspecs
    bundle = bundle(dependencies: {}, locked: [])

    files = bundle.app_files

    assert_equal [".bundle/config", "my_app.gemspec"], files.keys
    assert_equal "---\nBUNDLE_VERSION: \"system\"\nBUNDLE_FROZEN: \"true\"\nBUNDLE_PATH__SYSTEM: \"true\"\n" \
      "BUNDLE_AUTO_INSTALL: \"false\"\nBUNDLE_WITHOUT: \"development:test\"\n", files.fetch(".bundle/config")
    spec = Gem::Specification.from_yaml(Gem::Specification.load(File.join(@dir, "my_app", "my_app.gemspec")).to_yaml)
    evaluated = files.fetch("my_app.gemspec")
    refute_includes evaluated, "IO.popen"
    assert_includes evaluated, "s.name = \"my_app\".freeze"
    assert_equal spec.name, eval(evaluated, binding, "my_app.gemspec").name
  end

  def test_leaves_bundlers_own_root_as_it_found_it
    before = Bundler.root
    bundle(dependencies: {}, locked: [])

    assert_equal before, Bundler.root
  end
end
