# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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

  def gems(bundle, platform) = bundle.gems_for(platform, ruby_version: "4.0.9", arch: FakeRuntime::ARCH.fetch(platform.name))

  def names(bundle, platform) = gems(bundle, platform).map(&:to_s)

  def test_picks_the_build_bundler_would_pick_on_each_platform_and_follows_dependencies
    bundle = bundle(dependencies: { "foo" => ">= 0", "native" => ">= 0" },
      locked: [@bar, @foo, @linux, @musl, @windows, @darwin, @source],
      locked_dependencies: { @foo.lock_name => ["bar (>= 0)"] })

    assert_equal ["bar 2.0.0", "foo 1.0.0", "native 1.0.0 (x86_64-linux-gnu)"], names(bundle, LINUX)
    assert_equal ["bar 2.0.0", "foo 1.0.0", "native 1.0.0 (x64-mingw-ucrt)"], names(bundle, WINDOWS)
    assert_equal ["bar 2.0.0", "foo 1.0.0", "native 1.0.0 (arm64-darwin)"], names(bundle, DARWIN)
    gem = gems(bundle, LINUX).last
    assert_equal ["https://rubygems.org/", @linux.sha256], [gem.remote, gem.sha256]
  end

  # A built app's Bundler takes its platform from the runtime's Ruby
  # (Gem::Platform.local, from RbConfig's arch), arm64-darwin-23 for
  # rv-ruby's macOS build, whatever Mac it runs on, and finds a lockfile
  # platform or a gem's build fits as RubyGems' Gem::Platform#=== says:
  # arm64-darwin and arm64-darwin-23 do, arm64-darwin-24 does not.
  def test_a_macos_platform_with_a_darwin_version_counts_as_the_runtimes_bundler_counts_it
    darwin23 = FakeGem.build(@dir, "native", "1.0.0", platform: "arm64-darwin-23")
    darwin24 = FakeGem.build(@dir, "other", "1.0.0", platform: "arm64-darwin-24")
    other = FakeGem.build(@dir, "other", "1.0.0")
    here = Gem::Platform.local.to_s # Bundler, frozen, wants the computer reading the lockfile locked too
    bundle = bundle(dependencies: { "native" => ">= 0", "other" => ">= 0" }, locked: [darwin23, darwin24, other, @source],
      platforms: ["arm64-darwin-23", "x86_64-linux", here].uniq)

    assert_equal ["native 1.0.0 (arm64-darwin-23)", "other 1.0.0"], names(bundle, DARWIN)
    newer = bundle(name: "newer_app", dependencies: {}, locked: [], platforms: ["arm64-darwin-24", "x86_64-linux", here].uniq - ["arm64-darwin-23"])
    error = assert_raises(Fledge::Error) { names(newer, DARWIN) }
    assert_includes error.message, "locks no gems for arm64-darwin"
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

  # Bundler leaves out the gems of an optional group unless `with` names
  # it (Bundler::Definition#requested_groups), and a built app's Bundler
  # reads its own .bundle/config, so what the build ships and what that
  # file says must come from the same settings.
  def test_an_optional_group_is_left_out_unless_the_project_asks_for_it_with_bundlers_own_setting
    gemfile = "group :extras, optional: true do\n  gem \"foo\"\nend\ngroup :docs do\n  gem \"bar\"\nend\n"
    plain = bundle(dependencies: {}, locked: [@foo, @bar], gemfile:, lock_dependencies: %w[foo bar])

    assert_equal ["bar 2.0.0"], names(plain, LINUX)
    assert_includes plain.app_files.fetch(".bundle/config"), "BUNDLE_WITHOUT: \"development:test\"\n"
    refute_includes plain.app_files.fetch(".bundle/config"), "BUNDLE_WITH:"

    root = FakeProject.write(@dir, name: "with_app", dependencies: {}, locked: [@foo, @bar], gemfile:, lock_dependencies: %w[foo bar])
    FileUtils.mkdir_p(File.join(root, ".bundle"))
    File.write(File.join(root, ".bundle", "config"), "---\nBUNDLE_WITH: \"extras:development\"\nBUNDLE_WITHOUT: \"docs\"\n")
    chosen = Fledge::Bundle.new(Fledge::App.at(root))

    assert_equal ["foo 1.0.0"], names(chosen, LINUX)
    config = chosen.app_files.fetch(".bundle/config")
    assert_includes config, "BUNDLE_WITHOUT: \"development:test:docs\"\n"
    assert_includes config, "BUNDLE_WITH: \"extras\"\n"
  end

  # Bundler's settings store an empty list as no value at all
  # (Bundler::Settings#array_to_s and #set_key), so a `with` that names
  # only development or test, from the environment or the project's
  # .bundle/config, must still leave those groups out.
  def test_development_and_test_gems_are_left_out_whatever_with_says
    gemfile = "group :development do\n  gem \"foo\"\nend\ngroup :test do\n  gem \"bar\"\nend\n"
    %w[development test development:test].each do |with|
      ENV["BUNDLE_WITH"] = with
      assert_empty names(bundle(name: "env_#{with.tr(':', '_')}", dependencies: {}, locked: [@foo, @bar], gemfile:,
        lock_dependencies: %w[foo bar]), LINUX), "BUNDLE_WITH=#{with}"
    ensure
      ENV.delete("BUNDLE_WITH")
    end
    root = FakeProject.write(@dir, name: "config_app", dependencies: {}, locked: [@foo, @bar], gemfile:, lock_dependencies: %w[foo bar])
    FileUtils.mkdir_p(File.join(root, ".bundle"))
    File.write(File.join(root, ".bundle", "config"), "---\nBUNDLE_WITH: \"development:test\"\n")
    configured = Fledge::Bundle.new(Fledge::App.at(root))

    assert_empty names(configured, LINUX)
    refute_includes configured.app_files.fetch(".bundle/config"), "BUNDLE_WITH:"
  end

  def test_a_gem_limited_to_a_ruby_version_follows_the_runtimes
    bundle = bundle(dependencies: {}, locked: [@foo, @bar],
      gemfile: "gem \"foo\", platforms: :mri_40\ngem \"bar\", platforms: :ruby_33\n", lock_dependencies: %w[bar foo])

    assert_equal ["foo 1.0.0"], names(bundle, LINUX)
    assert_empty names(bundle, WINDOWS)
  end

  def test_a_platform_the_lockfile_does_not_lock_is_refused
    here = Gem::Platform.local.to_s # Bundler, frozen, wants the computer reading the lockfile locked too
    bundle = bundle(dependencies: {}, locked: [], platforms: ["arm64-darwin-25", "x86_64-linux-gnu", here].uniq)

    assert_empty names(bundle, LINUX)
    error = assert_raises(Fledge::Error) { names(bundle, DARWIN) }
    assert_equal "Gemfile.lock locks no gems for arm64-darwin. Run bundle lock --add-platform arm64-darwin, then build again.",
      error.message
  end

  def test_the_lockfile_is_read_as_a_frozen_one_whatever_the_environment_says
    frozen = ENV.delete("BUNDLE_FROZEN")
    bundle = bundle(dependencies: {}, locked: [], platforms: ["java"])

    error = assert_raises(Fledge::Error) { names(bundle, LINUX) }
    assert_includes error.message, "Gemfile.lock locks no gems for x86_64-linux"
  ensure
    ENV["BUNDLE_FROZEN"] = frozen if frozen
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

  # bundle lock --add-checksums leaves the entry of a gem's build empty
  # when Bundler did not install that build and its gem server lists no
  # checksum for it, as for a gem only in vendor/cache (Bundler 4.0.20's
  # Bundler::Definition#add_checksums); Bundler's own advice, to run
  # bundle install elsewhere, does not fill it.
  def test_an_empty_checksum_entry_says_how_to_fill_it
    root = FakeProject.write(@dir, dependencies: { "native" => ">= 0" }, locked: [@linux, @darwin])
    lockfile = File.join(root, "Gemfile.lock")
    File.write(lockfile, File.read(lockfile).sub(" sha256=#{@linux.sha256}", ""))

    error = assert_raises(Fledge::Error) { Fledge::Bundle.new(Fledge::App.at(root)) }

    assert_includes error.message, "Your lockfile has an empty CHECKSUMS entry for \"native\""
    assert error.message.end_with?("\nbundle lock --add-checksums fills a gem's entry only for a build Bundler installed on this computer, " \
      "or one its gem server lists a checksum for. Write the SHA-256 of each of native's .gem files after its entry in Gemfile.lock's " \
      "CHECKSUMS section, as sha256=HEX (shasum -a 256 vendor/cache/native-*.gem prints them), then build again."), error.message
  end

  def test_a_gemfile_without_a_lockfile_says_to_lock_it
    root = FakeProject.write(@dir, dependencies: {}, locked: [])
    File.delete(File.join(root, "Gemfile.lock"))

    error = assert_raises(Fledge::Error) { Fledge::Bundle.new(Fledge::App.at(root)) }
    assert_equal "#{root} has Gemfile but no Gemfile.lock. Run bundle lock, then build again.", error.message
  end

  # A project whose Gemfile takes "elsewhere" from the folder +path+, which
  # the lockfile's PATH section names.
  def path_project(path: "../elsewhere", folder: "elsewhere", extensions: [])
    FileUtils.mkdir_p(File.join(@dir, folder))
    File.write(File.join(@dir, folder, "elsewhere.gemspec"),
      "Gem::Specification.new { |s| s.name = 'elsewhere'; s.version = '1.0'; s.summary = 'x'; s.authors = ['x']; " \
        "s.extensions = #{extensions.inspect}; s.files = [] }\n")
    root = FakeProject.write(@dir, dependencies: {}, locked: [], gemfile: "gem \"elsewhere\", path: #{path.inspect}\n",
      lock_dependencies: ["elsewhere!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  elsewhere (1.0)\n")
    File.write(lock, "PATH\n  remote: #{path}\n  specs:\n    elsewhere (1.0)\n\n#{text}")
    root
  end

  # Bundler's own way to ship a path gem from outside the project is to
  # copy it to vendor/cache/NAME (bundle cache --all), which a Bundler that
  # finds it uses in place of the original path.
  def test_a_gem_from_a_folder_outside_the_project_ships_where_bundler_looks_for_its_copy
    gem = gems(Fledge::Bundle.new(Fledge::App.at(path_project)), LINUX).last

    assert_equal Fledge::PathGem.new(name: "elsewhere", version: "1.0", folder: File.join(@dir, "elsewhere"),
      app_path: "vendor/cache/elsewhere", glob: "{,*,*/*}.gemspec", inside: false), gem
  end

  def test_a_gem_outside_the_project_comes_from_the_developers_own_copy_in_vendor_cache_when_there_is_one
    root = path_project
    FileUtils.mkdir_p(File.join(root, "vendor", "cache"))
    FileUtils.mv(File.join(@dir, "elsewhere"), File.join(root, "vendor", "cache", "elsewhere"))

    gem = gems(Fledge::Bundle.new(Fledge::App.at(root)), LINUX).last

    assert_equal [File.join(root, "vendor", "cache", "elsewhere"), "vendor/cache/elsewhere"], [gem.folder, gem.app_path]
  end

  def test_a_gem_outside_the_project_that_is_not_there_names_the_gem_and_what_to_do
    root = path_project
    FileUtils.rm_rf(File.join(@dir, "elsewhere"))

    error = assert_raises(Fledge::Error) { names(Fledge::Bundle.new(Fledge::App.at(root)), LINUX) }
    assert_equal "Gemfile.lock takes elsewhere from #{File.join(@dir, 'elsewhere')}, outside the project, and that folder is not " \
      "there. Check out elsewhere there, or move it into the project, or take it from a gem server.", error.message
  end

  def test_a_gem_outside_the_project_whose_path_names_no_folder_is_refused
    root = path_project(path: "../elsewhere/..", folder: "elsewhere")

    error = assert_raises(Fledge::Error) { names(Fledge::Bundle.new(Fledge::App.at(root)), LINUX) }
    assert_includes error.message, "takes elsewhere from ../elsewhere/.., outside the project, and a path that ends in \"..\" names no folder"
  end

  def test_a_path_gem_inside_the_project_ships_with_it_unless_it_has_an_extension
    root = path_project(path: "gems/elsewhere", folder: "my_app/gems/elsewhere")

    assert_empty gems(Fledge::Bundle.new(Fledge::App.at(root)), LINUX)
  end

  # Bundler never compiles a path gem's extension; bundle exec loads what
  # the developer last compiled there, for their own Ruby.
  def test_a_path_gem_with_an_extension_is_compiled_for_the_runtimes_ruby_wherever_it_is
    inside = path_project(path: "gems/elsewhere", folder: "my_app/gems/elsewhere", extensions: ["ext/e/extconf.rb"])
    gem = gems(Fledge::Bundle.new(Fledge::App.at(inside)), LINUX).grep(Fledge::PathGem).first

    assert_equal [true, "gems/elsewhere"], [gem.inside, gem.app_path]

    root = FakeProject.write(@dir, name: "ext_app", dependencies: {}, locked: [])
    File.write(File.join(root, "ext_app.gemspec"), File.read(File.join(root, "ext_app.gemspec"))
      .sub("spec.bindir", "spec.extensions = [\"ext/ext_app/extconf.rb\"]\n  spec.bindir"))
    own = gems(Fledge::Bundle.new(Fledge::App.at(root)), LINUX)

    assert_equal [[".", true]], own.map { |candidate| [candidate.app_path, candidate.inside] }
  end

  # A project whose Gemfile takes "g" from git, locked at +revision+,
  # with +options+ (tag, glob, submodules) in its GIT section.
  def git_project(revision: "a" * 40, options: "  tag: v1.0\n  glob: gems/*/*.gemspec\n")
    root = FakeProject.write(@dir, dependencies: {}, locked: [],
      gemfile: "gem \"g\", git: \"https://example.com/repo.git\", tag: \"v1.0\", glob: \"gems/*/*.gemspec\"\n",
      lock_dependencies: ["g!"])
    lock = File.join(root, "Gemfile.lock")
    text = File.read(lock).sub("CHECKSUMS\n", "CHECKSUMS\n  g (1.0)\n")
    File.write(lock, "GIT\n  remote: https://example.com/repo.git\n  revision: #{revision}\n#{options}  specs:\n    g (1.0)\n\n#{text}")
    root
  end

  # The lockfile's revision pins a git gem, as its checksum pins a .gem.
  def test_a_gem_from_git_is_taken_at_the_revision_the_lockfile_locks
    gems = gems(Fledge::Bundle.new(Fledge::App.at(git_project)), LINUX)

    assert_equal [
Fledge::GitGem.new(name: "g", version: "1.0", uri: "https://example.com/repo.git", revision: "a" * 40,
  glob: "gems/*/*.gemspec", ref: "tag v1.0", submodules: false,),
], gems
  end

  def test_a_git_gem_without_a_full_revision_is_refused
    error = assert_raises(Fledge::Error) { names(Fledge::Bundle.new(Fledge::App.at(git_project(revision: "abc1234"))), LINUX) }

    assert_equal "Gemfile.lock takes g from https://example.com/repo.git without pinning it to a commit (its revision is " \
      "\"abc1234\"), and Fledge ships a git gem only at the full commit the lockfile locks. Run bundle lock, then build again.",
      error.message
  end

  def test_a_git_gem_that_asks_for_submodules_carries_the_request_to_its_checkout
    root = git_project(options: "  tag: v1.0\n  glob: gems/*/*.gemspec\n  submodules: true\n")
    File.write(File.join(root, "Gemfile"), File.read(File.join(root, "Gemfile")).sub("glob: \"gems/*/*.gemspec\"", "glob: \"gems/*/*.gemspec\", submodules: true"))

    assert_equal [true], gems(Fledge::Bundle.new(Fledge::App.at(root)), LINUX).map(&:submodules)
    assert_equal [false], gems(Fledge::Bundle.new(Fledge::App.at(git_project)), LINUX).map(&:submodules)
  end

  # bundle config build.NAME, at any level Bundler reads, as Bundler
  # passes it to the gem's extconf.rb (Bundler::GemInstaller#spec_settings).
  def test_build_options_are_bundlers_split_as_a_shell_would
    root = FakeProject.write(@dir, dependencies: {}, locked: [])
    FileUtils.mkdir_p(File.join(root, ".bundle"))
    File.write(File.join(root, ".bundle", "config"), "---\nBUNDLE_BUILD__NOKOGIRI: \"--use-system-libraries --with-opt='a b'\"\n")

    bundle = Fledge::Bundle.new(Fledge::App.at(root))

    assert_equal ["--use-system-libraries", "--with-opt=a b"], bundle.build_args("nokogiri")
    assert_empty bundle.build_args("other")
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
