# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/binaries"
require_relative "support/gem_app_build"

# fledge build for a gem-shaped app, through real streams: real
# .gem files, built by RubyGems, served by a real HTTP server at the
# lockfile's remote, into fake runtimes.
class GemAppBuildTest < Minitest::Test
  include GemAppBuild

  def test_the_locked_gems_ship_for_each_platform_beside_the_runtimes_own
    root, linux, = locked_gems_project

    out, err, status = build(File.join(root, "exe/my_app"))
    assert_equal [0, "dist/MyApp-x86_64-linux.tar.gz\n"], [status, out], err
    assert_the_locked_gems_ship("dist/MyApp-x86_64-linux", "lib/ruby/gems/4.1.0+5", linux)
    assert_equal 1, err.scan("Downloading native-1.0.0-x86_64-linux-gnu.gem from #{@server.url('/')}").size
    assert_equal 1, @server.requests.count("/gems/foo-1.0.0.gem"), "a gem downloaded once is taken from the cache"
  end

  # Ruby bundles rdoc, whose RubyGems plugin has a loader in the gem
  # folder's plugins/ already, and irb, which Rails and many other
  # Gemfiles lock, asks for a newer rdoc. Gem::Installer#generate_plugins
  # writes the same loader name for it; the runtime's loader stays, and
  # the build still succeeds (Rooibos' own Gemfile locked such an rdoc).
  def test_a_locked_gem_with_a_plugin_the_runtime_already_has_a_loader_for_ships_beside_it
    rdoc = FakeGem.build(@gems, "rdoc", "7.1.0", plugin: true)
    root = project(dependencies: { "rdoc" => ">= 0" }, locked: [rdoc])

    out, err, status = build(File.join(root, "exe/my_app"))

    assert_equal [0, "dist/MyApp-x86_64-linux.tar.gz\n"], [status, out], err
    gems = File.join(@dir, "dist/MyApp-x86_64-linux/lib/ruby/gems/4.1.0+5")
    assert_path_exists File.join(gems, "gems/rdoc-7.1.0/lib/rubygems_plugin.rb")
    assert_equal "require_relative '../gems/rdoc-7.0.4/lib/rubygems_plugin.rb'\n", File.read(File.join(gems, "plugins/rdoc_plugin.rb"))
  end

  # The Bundler a lockfile's BUNDLED WITH names, which bundle exec runs in
  # place of Ruby's own, ships installed beside the runtime's own
  # Bundler, from RubyGems.org (here through Bundler's mirror of it, the
  # loopback server), and fledge.cfg names it for the launcher. A
  # lockfile the runtime's own Bundler wrote ships none.
  def test_the_bundler_the_lockfile_names_ships_and_the_launcher_is_told_to_run_it
    runtime_bundler = Fledge::Entry.file("lib/ruby/gems/4.1.0+5/specifications/default/bundler-4.0.20.gemspec", "# bundler\n")
    FakeRuntime.write(@runtimes, Fledge::Platform.find("x86_64-linux"), extra: [runtime_bundler])
    bundler = FakeGem.build(@gems, "bundler", "4.0.19", files: { "lib/bundler.rb" => "# bundler\n" }, executables: [])
    serve(bundler)
    root = project(dependencies: {}, locked: [], bundled_with: "4.0.19", bundler:)
    FileUtils.mkdir_p(File.join(root, ".bundle"))
    File.write(File.join(root, ".bundle", "config"), "---\nBUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG/: \"#{@server.url('/')}\"\n")

    out, err, status = build(File.join(root, "exe/my_app"))

    assert_equal [0, "dist/MyApp-x86_64-linux.tar.gz\n"], [status, out], err
    folder = File.join(@dir, "dist/MyApp-x86_64-linux")
    gems = File.join(folder, "lib/ruby/gems/4.1.0+5")
    assert_equal "# bundler\n", File.read(File.join(gems, "gems/bundler-4.0.19/lib/bundler.rb"))
    assert_equal "4.0.19", Gem::Specification.load(File.join(gems, "specifications/bundler-4.0.19.gemspec")).version.to_s
    assert_includes File.read(File.join(folder, "fledge.cfg")), "\ngemfile = Gemfile\nbundler = 4.0.19\n"

    File.write(File.join(root, "Gemfile.lock"), File.read(File.join(root, "Gemfile.lock")).sub("BUNDLED WITH\n  4.0.19", "BUNDLED WITH\n  4.0.20"))
    _, err, status = build(File.join(root, "exe/my_app"))
    assert_equal 0, status, err
    refute_includes File.read(File.join(folder, "fledge.cfg")), "bundler ="
    refute_path_exists File.join(gems, "gems/bundler-4.0.19")
  end

  def test_a_gem_the_lockfile_does_not_lock_for_the_platform_says_what_to_run
    native = FakeGem.build(@gems, "native", "1.0.0", platform: "x86_64-linux-gnu")
    root = project(dependencies: { "native" => ">= 0" }, locked: [native], platforms: %w[x86_64-linux arm64-darwin])

    _, err, status = build(root, host: "x64-mingw-ucrt")

    assert_equal 1, status
    assert_equal "fledge build: Gemfile.lock locks no gems for x64-mingw-ucrt. Run bundle lock --add-platform x64-mingw-ucrt, " \
      "then build again.\n", err
    _, err, = build(root, host: "arm64-darwin-23")
    assert_equal "fledge build: Gemfile.lock locks no build of native for arm64-darwin, only for x86_64-linux-gnu. " \
      "If native has one, run bundle lock --add-platform arm64-darwin, then build again.\n", err
    refute_path_exists File.join(@dir, "dist/MyApp-arm64-darwin")
  end

  # A precompiled build whose required_ruby_version excludes the
  # runtime's Ruby gives way to the gem's source build, as the built
  # app's Bundler would choose it, and when the source build excludes it
  # too, the build names the precompiled one, as Bundler would fail on it.
  def test_a_precompiled_build_for_another_ruby_gives_way_to_the_source_build
    precompiled = FakeGem.build(@gems, "lite", "1.0.0", platform: "x86_64-linux-gnu", required_ruby_version: "< 3.5")
    source = FakeGem.build(@gems, "lite", "1.0.0")
    root = project(dependencies: { "lite" => ">= 0" }, locked: [precompiled, source])

    out, err, status = build(root)

    assert_equal [0, "dist/MyApp-x86_64-linux.tar.gz\n"], [status, out], err
    gems = File.join(@dir, "dist/MyApp-x86_64-linux/lib/ruby/gems/4.1.0+5")
    assert_path_exists File.join(gems, "gems/lite-1.0.0/lib/lite.rb")
    refute_path_exists File.join(gems, "gems/lite-1.0.0-x86_64-linux-gnu")

    FileUtils.rm_rf([root, File.join(@dir, "dist"), File.join(@dir, "cache")])
    neither = FakeGem.build(File.join(@gems, "old"), "lite", "1.0.0", required_ruby_version: "< 3.5")
    root = project(dependencies: { "lite" => ">= 0" }, locked: [precompiled, neither])
    _, err, status = build(root)
    assert_equal 1, status
    assert_includes err, "lite 1.0.0 (x86_64-linux-gnu) needs Ruby < 3.5, and Fledge's runtime is Ruby 4.1.0."
  end

  # Fledge refuses a gem only when it would not run where the app goes,
  # and names every such gem at once.
  def test_every_gem_that_would_not_run_is_named_with_what_to_do
    TestReaders.need(self, :elf)
    old = FakeGem.build(@gems, "old", "1.0.0", platform: "x86_64-linux-gnu", required_ruby_version: "< 3.5")
    unloadable = FakeGem.build(@gems, "unloadable", "1.0.0", platform: "x86_64-linux-gnu",
      files: { "lib/unloadable.so" => Binaries.elf(needed: %w[libc.so.6 libxml2.so.2]) })
    root = project(dependencies: { "old" => ">= 0", "unloadable" => ">= 0" }, locked: [old, unloadable])

    out, err, status = build(root)

    assert_equal [1, ""], [status, out]
    assert_equal [
      "fledge build: MyApp can't ship for x86_64-linux:",
      "fledge build:   old 1.0.0 (x86_64-linux-gnu) needs Ruby < 3.5, and Fledge's runtime is Ruby 4.1.0.",
      "fledge build:   unloadable 1.0.0 (x86_64-linux-gnu)'s lib/unloadable.so needs libxml2.so.2, which neither linux, nor " \
        "Fledge's runtime, nor the gem itself provides, so the app could not load it on another computer. Build the gem so " \
        "that it carries the library, or links it statically, or, when every computer the app goes to has it from its Linux " \
        "distribution, list it in fledge.yml as linux: { system_libraries: [libxml2.so.2] }.",
    ], err.lines.map(&:chomp).grep_v(/\ADownloading /)
    assert_empty Dir.glob(File.join(@dir, "dist", "*"))
  end

  # On a Mac, a gem that links a library from this computer, such as
  # Homebrew's SDL, is refused with the setting that carries it; with the
  # library listed, the build looks for it where dyld would, and refuses
  # one it does not find there, or one listed that nothing needs, both in
  # the same list as every other problem. Fledge's objdump reads Mach-O
  # only on a Mac; test/integration/carried_libraries_test.rb builds an
  # app that carries one.
  def test_a_mac_apps_gem_that_links_a_library_from_this_computer_is_refused_until_the_project_lists_it
    skip "fledge build reads Mach-O files with Xcode's objdump, which only a Mac has" unless TestReaders.os == "darwin"
    library = "@rpath/libffi.dylib"
    sdlish = FakeGem.build(@gems, "sdlish", "1.0.0", platform: "arm64-darwin",
      files: { "lib/sdlish.bundle" => Binaries.macho(needed: ["/usr/lib/libSystem.B.dylib", library]) })
    root = project(dependencies: { "sdlish" => ">= 0" }, locked: [sdlish], platforms: %w[arm64-darwin])
    bundle = "lib/ruby/gems/4.1.0+5/gems/sdlish-1.0.0-arm64-darwin/lib/sdlish.bundle"

    _, err, status = build(root, host: "arm64-darwin-23")
    assert_equal 1, status
    assert_includes err, "sdlish 1.0.0 (arm64-darwin)'s lib/sdlish.bundle needs #{library}, which neither darwin, nor Fledge's runtime, " \
      "nor the gem itself provides, so the app could not load it on another computer. Build the gem so that it carries " \
      "the library, or links it statically, or, if you may distribute it, list it in fledge.yml as macos: { " \
      "carried_libraries: [libffi.dylib] } to have the app carry it from this computer.\n"

    File.write(File.join(root, "fledge.yml"), "macos:\n  carried_libraries: [libffi.dylib, libunused.dylib]\n")
    out, err, status = build(root, host: "arm64-darwin-23")
    assert_equal [1, ""], [status, out]
    assert_equal [
      "fledge build: MyApp can't ship for arm64-darwin:",
      "fledge build:   #{bundle} needs #{library}, which fledge.yml's macos: carried_libraries has the app carry, but none of the run " \
        "paths dyld would search for it on this computer (it has none) leads to a file, so there is nothing to copy. Install it, or " \
        "build the gem so that it names the library where it is.",
      "fledge build:   fledge.yml's macos: carried_libraries lists libunused.dylib, which none of the gems' compiled files, nor the " \
        "libraries the app carries, needs. Remove it.",
    ], err.lines.map(&:chomp).grep_v(/\ADownloading /)
    assert_empty Dir.glob(File.join(@dir, "dist", "*"))
  end

  # A gem for every platform may carry a library for each processor and
  # load the one for its own, as raylib-bindings does: each app's build
  # judges its own processor's file, and ships the other unjudged, as
  # bundle exec has it.
  def test_a_library_for_another_processor_ships_unjudged
    TestReaders.need(self, :elf)
    foreign = Binaries.elf(needed: %w[libc.so.6 libGLX.so.0], cpu: "aarch64")
    rayish = FakeGem.build(@gems, "rayish", "1.0.0",
      files: { "lib/libray.x86_64.so" => Binaries.elf(needed: %w[libc.so.6]), "lib/libray.aarch64.so" => foreign })
    root = project(dependencies: { "rayish" => ">= 0" }, locked: [rayish], platforms: %w[x86_64-linux aarch64-linux])

    out, err, status = build(root)

    assert_equal [0, "dist/MyApp-x86_64-linux.tar.gz\n"], [status, out], err
    assert_equal foreign, File.binread(File.join(@dir, "dist/MyApp-x86_64-linux/lib/ruby/gems/4.1.0+5/gems/rayish-1.0.0/lib/libray.aarch64.so"))
    _, err, status = build(root, host: "aarch64-linux")
    assert_equal 1, status
    assert_includes err, "rayish 1.0.0's lib/libray.aarch64.so needs libGLX.so.0"
  end

  # A gem may need a library the project lists as the Linux
  # distribution's, and the app's program is told to look for
  # it; a library listed that no gem needs from the system fails the
  # build, as a gem that needs one unlisted does.
  def test_a_library_listed_as_the_distributions_lets_a_gem_ship_on_linux
    TestReaders.need(self, :elf)
    wrapper = FakeGem.build(@gems, "wrapper", "1.0.0", platform: "x86_64-linux-gnu",
      files: { "lib/wrapper.so" => Binaries.elf(needed: %w[libc.so.6 libxml2.so.2]) })
    root = project(dependencies: { "wrapper" => ">= 0" }, locked: [wrapper])
    File.write(File.join(root, "fledge.yml"), "linux:\n  system_libraries: [libxml2.so.2]\n")

    out, err, status = build(File.join(root, "exe/my_app"))
    assert_equal [0, "dist/MyApp-x86_64-linux.tar.gz\n"], [status, out], err
    assert_includes File.read(File.join(@dir, "dist/MyApp-x86_64-linux/fledge.cfg")), "\nsystem_libraries = libxml2.so.2\n"

    File.write(File.join(root, "fledge.yml"), "linux:\n  system_libraries: [libxml2.so.2, libgtk-3.so.0]\n")
    out, err, status = build(File.join(root, "exe/my_app"))
    assert_equal [1, ""], [status, out]
    assert_equal [
      "fledge build: MyApp can't ship for x86_64-linux:",
      "fledge build:   fledge.yml's linux: system_libraries lists libgtk-3.so.0, which none of the gems' compiled files needs beyond " \
        "what every Linux distribution, Fledge's runtime, and the gems themselves provide. Remove it.",
    ], err.lines.map(&:chomp).grep_v(/\ADownloading /)
  end

  # The gems an app depends on, and their licenses, are its developer's
  # choice and responsibility, not Fledge's (the maintainer's words of
  # 2026-10-28). So every one of these ships: a GPL gem, an
  # AGPL native gem shaped like Tokra, a gem that declares no license, a
  # precompiled LGPL gem whose source the lockfile does not pin, an MPL
  # gem, one that names a license SPDX does not know, and a native gem
  # with GNU libiconv's code compiled into it, as nokogiri's precompiled
  # macOS and Windows builds have, that no one has reviewed.
  def test_a_gem_ships_whatever_its_license_and_whatever_its_compiled_files_hold
    TestReaders.need(self, :elf)
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

    _, err, status = build(root)

    assert_equal 0, status, err
    assert_empty err.lines.grep_v(/\ADownloading /), "no warnings, and no verdicts"
    installed = File.join(@dir, "dist/MyApp-x86_64-linux/lib/ruby/gems/4.1.0+5")
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

      _, err, status = build(root)

      assert_equal 1, status
      assert_equal "fledge build: #{File.join(root, 'fledge.yml')} has #{key}, which Fledge does not know. It knows #{Fledge::Config::KNOWN}.\n", err
    end
  end

  def test_a_gem_whose_file_differs_from_the_lockfile_is_refused
    foo = FakeGem.build(@gems, "foo", "1.0.0")
    root = project(dependencies: { "foo" => ">= 0" }, locked: [foo])
    @routes["/gems/foo-1.0.0.gem"] = [200, {}, "not the gem"]

    _, err, status = build(root)

    assert_equal 1, status
    assert_match(/\Afledge build: .*foo-1\.0\.0\.gem.*SHA-256/, err.lines.grep(/SHA-256/).first.to_s)
  end
end
