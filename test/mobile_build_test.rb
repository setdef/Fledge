# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"
require_relative "support/binaries"
require_relative "support/fake_extensions"
require_relative "support/loopback_server"
require "stringio"
require "yaml"

# fledge build ios and fledge build android, through real
# streams, with fake mobile runtimes shaped as
# a phone's runtime holds them, real .gem files served at the lockfile's remote,
# and, for iOS, the real XcodeGen where this computer has it.
class MobileBuildTest < Minitest::Test
  # The lines of fledge.links that link the fake Android runtime's one
  # gem's command, bin/rake, to the ruby program for each ABI.
  RAKE_LINKS = "arm64-v8a\tlibfledgerubyexe.so\tbin/rake\nx86_64\tlibfledgerubyexe.so\tbin/rake\n"

  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, ".git"))
    @runtimes = File.join(@dir, "runtimes")
    FileUtils.mkdir_p(@runtimes)
    Fledge::MobilePlatform.names.each { |name| FakeRuntime.write_mobile(@runtimes, Fledge::MobilePlatform.find(name)) }
    @gems = File.join(@dir, "gems")
    FileUtils.mkdir_p(@gems)
    @routes = {}
    @server = LoopbackServer.new(@routes)
  end

  def teardown
    @server.stop
    FileUtils.rm_rf(@dir)
  end

  def build(*argv, host: "x86_64-linux", ruby: RUBY_VERSION)
    out = StringIO.new
    err = StringIO.new
    env = { "FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache") }
    command = Fledge::CLI::Build.new(out:, err:, env:, host: Gem::Platform.new(host), ruby:, pins: FakeRuntime.pins(@runtimes),
      gemspec_loads: NO_GEMSPEC_LOADS)
    status = Dir.chdir(@dir) { command.call(argv) }
    [out.string, err.string, status]
  end

  # A phone's Ruby is the minor version that runs fledge build too;
  # the fake runtimes are Ruby 4.1.0.
  def test_a_phone_project_on_another_ruby_minor_than_the_runtimes_fails
    script_app("identifier: com.example.Hello\n")
    out, err, status = build("android", "hello", ruby: "4.2.0")

    assert_equal [1, ""], [status, out]
    assert_includes err, "fledge build: You are running Ruby 4.2.0, and Fledge #{Fledge::VERSION}'s runtime for android is Ruby 4.1.0.\n"
    refute_path_exists File.join(@dir, "dist/Hello-android")
  end

  # fledge android project writes the project as the build for the phone
  # does, with the phone given, and its errors name that command.
  def test_a_phones_project_command_writes_its_project_and_names_itself_in_errors
    root = script_app("identifier: com.example.Hello\n")
    env = { "FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache") }
    project = lambda do |ruby|
      out = StringIO.new
      err = StringIO.new
      command = Fledge::CLI::Build.new(out:, err:, env:, host: Gem::Platform.new("x86_64-linux"), ruby:, pins: FakeRuntime.pins(@runtimes),
        gemspec_loads: NO_GEMSPEC_LOADS, phone: Fledge::MobilePlatform.new(name: "android"))
      [Dir.chdir(@dir) { command.call([root]) }, out.string, err.string]
    end

    assert_equal [0, "dist/Hello-android\n", ""], project.call(RUBY_VERSION)
    status, _, err = project.call("4.2.0")
    assert_equal 1, status
    assert_includes err, "fledge android project: You are running Ruby 4.2.0"
  end

  # A lone script with the fledge.yml +config+ and, when +icons+ names
  # sizes, an icon's PNG of each, as icons/app-SIZE.png.
  def script_app(config, icons: [])
    root = FakeApp.write(@dir)
    File.write(File.join(root, "fledge.yml"), config)
    FileUtils.mkdir_p(File.join(root, "icons"))
    icons.each { |size| File.write(File.join(root, "icons", "app-#{size}.png"), "PNG #{size}") }
    root
  end

  def gem_project(dependencies:, locked:, **)
    locked.each { |gem| @routes["/gems/#{gem.file_name}"] = [200, {}, File.binread(gem.path)] }
    root = FakeProject.write(@dir, dependencies:, locked:, remote: @server.url("/"), **)
    File.write(File.join(root, "fledge.yml"), "identifier: com.example.MyApp\n")
    root
  end

  def read(*path)
    File.read(File.join(@dir, *path))
  end

  def test_an_android_project_holds_the_runtime_the_app_and_its_identity
    root = script_app(<<~YAML, icons: Fledge::Icon::ANDROID.values)
      name: Bob's & Co
      identifier: com.example.BobsApp
      version: "2.3.4"
      icon: icons/app
    YAML

    out, err, status = build("android", root)

    assert_equal [0, "dist/Bob's & Co-android\n", ""], [status, out, err]
    project = File.join(@dir, "dist", "Bob's & Co-android")
    assert_equal "# Written by fledge build: what this app's program runs.\nentry = main.rb\nidentifier = com.example.BobsApp\n",
      File.read(File.join(project, "fledge/fledge.cfg"))
    assert_equal "puts 'hi'\n", File.read(File.join(project, "fledge/app/main.rb"))
    assert_equal "# stdlib\n", File.read(File.join(project, "fledge/lib/ruby/stdlib.rb")), "the runtime's Ruby is the asset's"
    assert_equal "certificates\n", File.read(File.join(project, "fledge/libexec/cert.pem"))
    assert_equal "/* ruby.h */\n", File.read(File.join(project, "fledge/include/ruby-4.1.0+5/ruby.h")), "mkmf finds Ruby's headers"
    refute_path_exists File.join(project, "fledge/include/fledge_ruby.h"), "the app's Ruby has Ruby's headers, not the embedding API's"
    assert_equal "Fledge's runtime for android\n", File.read(File.join(project, "fledge/notices/NOTICES.txt")), "the app carries the notices"
    assert_equal "PK aar", File.read(File.join(project, "libs/FledgeRuby.aar"))
    # Windows keeps no executable bit, and runs the wrapper's batch file.
    assert File.executable?(File.join(project, "gradlew")), "Gradle's wrapper runs as it is" unless Gem.win_platform?
    assert_path_exists File.join(project, "gradlew.bat")

    gradle = File.read(File.join(project, "build.gradle"))
    assert_includes gradle, "applicationId = 'com.example.BobsApp'"
    assert_includes gradle, "versionCode = 2003004"
    assert_includes gradle, "versionName = '2.3.4'"
    settings = File.read(File.join(project, "settings.gradle"))
    assert_includes settings, "rootProject.name = 'Bob\\'s & Co'"
    assert_includes settings, "id 'com.android.application' version '#{Fledge::MobileProject::Android::AGP}'"
    assert_includes File.read(File.join(project, "src/main/res/values/strings.xml")), "<string name=\"app_name\">Bob\\'s &amp; Co</string>"
    assert_includes File.read(File.join(project, "src/main/AndroidManifest.xml")),
      '<application android:label="@string/app_name" android:icon="@mipmap/ic_launcher">'
    Fledge::Icon::ANDROID.each do |density, size|
      assert_equal "PNG #{size}", File.read(File.join(project, "src/main/res/mipmap-#{density}/ic_launcher.png"))
    end
    leftover = Dir.glob("**/*", File::FNM_DOTMATCH, base: project).select { |path| File.file?(File.join(project, path)) }
      .grep_v(/\.(?:jar|aar|pem)\z/).select { |path| File.read(File.join(project, path)).match?(Fledge::MobileProject::TOKEN) }
    assert_empty leftover, "every mark in the template is filled"
  end

  # Android lets an app run only its native libraries, so a gem's
  # command, bin/NAME, is a link to the runtime's ruby program, which
  # fledge.links makes as the app starts, and RubyGems' wrapper is kept
  # in libexec/commands, where the app's Ruby reads it in that link's
  # place.
  def test_an_android_apps_gem_commands_are_links_to_its_ruby_program
    root = script_app("identifier: com.example.hello\n")

    assert_equal 0, build("android", root)[2]
    project = File.join(@dir, "dist/Hello-android")
    assert_equal "#!/bin/sh\n# rake's wrapper\n", File.read(File.join(project, "fledge/libexec/commands/rake"))
    assert_equal FakeRuntime::ANDROID_LINKS + RAKE_LINKS, File.read(File.join(project, "fledge/fledge.links"))
    refute_path_exists File.join(project, "fledge/bin")
  end

  # A locked gem's command gets RubyGems' wrapper for it, written as the
  # phone's RubyGems writes one (Fledge::GemWrapper), with no desktop
  # runtime to run: FLEDGE_RUNTIME_DIR here holds only the phones', as
  # on the computers CI writes an Android project on.
  def test_an_android_apps_locked_gems_commands_need_no_desktop_runtime
    tool = FakeGem.build(@gems, "tool", "1.0.0", executables: %w[tool],
      files: { "lib/tool.rb" => "# tool\n", "exe/tool" => "#!/usr/bin/env ruby -w\nputs 'tool'\n" })
    root = gem_project(dependencies: { "tool" => ">= 0" }, locked: [tool], platforms: %w[ruby arm64-darwin x86_64-linux])
    assert_equal ["fledge-runtime-#{Fledge::VERSION}-android.tar.gz", "fledge-runtime-#{Fledge::VERSION}-ios.tar.gz"],
      Dir.children(@runtimes).grep(/\.tar\.gz\z/).sort, "only the phones' runtimes are at hand"

    out, err, status = build("android", root)

    assert_equal [0, "dist/MyApp-android\n"], [status, out], err
    root = File.join(@dir, "dist/MyApp-android/fledge")
    wrapper = File.read(File.join(root, "libexec/commands/tool"))
    assert wrapper.start_with?("#!/bin/sh\n# -*- ruby -*-\n"), wrapper
    assert_includes wrapper, "\n#!/usr/bin/env ruby -w\n"
    assert_includes wrapper, "Gem.activate_and_load_bin_path('tool', 'tool', version)"
    assert_includes File.read(File.join(root, "fledge.links")), "x86_64\tlibfledgerubyexe.so\tbin/tool\n"
  end

  def test_an_app_without_an_icon_gets_the_systems_own
    root = script_app("identifier: com.example.Hello\n")

    _, err, status = build("android", root)

    assert_equal 0, status, err
    assert_includes read("dist/Hello-android/src/main/AndroidManifest.xml"), "<application android:label=\"@string/app_name\">"
    assert_empty Dir.glob(File.join(@dir, "dist/Hello-android/src/main/res/mipmap-*"))
    assert_includes read("dist/Hello-android/build.gradle"), "versionCode = 1\n", "0.0.0 is Android's lowest versionCode"
  end

  def test_a_phones_project_needs_an_identifier_and_its_icons
    root = script_app("icon: icons/app\n")

    _, err, status = build("android", root)

    assert_equal 1, status
    assert_equal "fledge build: #{File.join(root, 'fledge.yml')}: an Android app needs an identifier, the reverse-DNS name the " \
      "system and its store know the app by, such as identifier: com.example.Hello\n", err
    File.write(File.join(root, "fledge.yml"), "identifier: com.example.Hello\nicon: icons/app\n")
    _, err, = build("android", root)
    assert_equal "fledge build: the icon icons/app-48.png does not exist. fledge.yml's icon names the icon's files without an " \
      "extension, as Briefcase's does. Android apps take one PNG of each size, -48, -72, -96, -144, -192, one for each screen density.\n", err
    refute_path_exists File.join(@dir, "dist/Hello-android")
  end

  def test_android_refuses_an_identifier_it_cannot_take
    root = script_app("identifier: com.example.my-app.2d\n")

    _, err, status = build("android", root)

    assert_equal 1, status
    assert_equal "fledge build: #{File.join(root, 'fledge.yml')}: Android takes com.example.my-app.2d for no applicationId: each " \
      "part between its dots must begin with a letter and hold only letters, digits, and underscores, such as " \
      "com.example.my_app.a2d\n", err
  end

  def test_each_phones_project_is_built_where_its_tools_run
    root = script_app("identifier: com.example.Hello\n")

    _, err, status = build("ios", root, host: "x86_64-linux")
    assert_equal [
      1,
      "fledge build: An iOS app's project is built with Xcode, which runs only on macOS, and this computer is " \
        "x86_64-linux. Build it on arm64-darwin.\n",
], [status, err]
    _, err, = build("android", root, host: "aarch64-linux")
    assert_equal "fledge build: An Android app's project is built with the Android SDK, which Google supports on macOS, Windows, " \
      "and x86-64 Linux, and this computer is aarch64-linux. Build it on arm64-darwin, x86_64-linux, x64-mingw-ucrt.\n", err
    assert_equal 0, build("android", root, host: "arm64-darwin-24").last
  end

  def test_an_ios_project_is_xcodegens_with_the_slices_ruby_and_the_apps_icon
    root = script_app(<<~YAML, icons: [Fledge::Icon::IOS])
      name: My App
      identifier: com.example.MyApp
      version: "1.2.3.pre.4"
      icon: icons/app
    YAML

    out, err, status = build("ios", root, host: "arm64-darwin-24")

    project = File.join(@dir, "dist", "My App-ios")
    unless xcodegen?
      assert_equal 1, status
      assert_match(/\Afledge build: fledge build needs xcodegen, which it could not run \(.*\)\. Install XcodeGen/, err)
      return refute_path_exists(project)
    end

    assert_equal [0, "dist/My App-ios\n", ""], [status, out, err]
    assert_path_exists File.join(project, "My App.xcodeproj/project.pbxproj")
    spec = YAML.safe_load_file(File.join(project, "project.yml"))
    assert_equal "My App", spec.fetch("name")
    settings = spec.dig("targets", "My App", "settings", "base")
    assert_equal ["My App", "com.example.MyApp", "1.2.3", "1.2.3", "AppIcon"],
      settings.values_at("PRODUCT_NAME", "PRODUCT_BUNDLE_IDENTIFIER", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION",
        "ASSETCATALOG_COMPILER_APPICON_NAME")
    assert_equal "PNG 1024", File.read(File.join(project, "Host/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
    assert_path_exists File.join(project, "Host/PrivacyInfo.xcprivacy")
    assert_equal "# stdlib\n", File.read(File.join(project, "FledgeRuby.xcframework/ios-arm64-simulator/lib/ruby/stdlib.rb"))
    assert_equal "puts 'hi'\n", File.read(File.join(project, "fledge/app/main.rb"))
    assert_path_exists File.join(project, "fledge/fledge.cfg")
    refute_path_exists File.join(project, "fledge/lib"), "the build copies each slice's Ruby, so ROOT holds none of its own"
    copy = spec.dig("targets", "My App", "postCompileScripts", 0, "script")
    assert_includes copy, "ditto \"$PROJECT_DIR/FledgeRuby.xcframework/$slice/include\" \"$root/include\"\n", "mkmf finds Ruby's headers"
  end

  # Every app's Ruby runs on the main thread, whatever its kind, as under
  # ruby main.rb, so every app's main thread has the 64 MB stack Ruby
  # had on a thread of its own, and the project switches nothing by kind.
  def test_every_ios_apps_main_thread_has_rubys_stack_whatever_its_kind
    skip "this computer has no XcodeGen" unless xcodegen?
    settings = %w[console windowed].map do |kind|
      root = script_app("identifier: com.example.Hello\nkind: #{kind}\n")
      _, err, status = build("ios", root, host: "arm64-darwin-24")
      assert_equal 0, status, err
      base = YAML.safe_load_file(File.join(@dir, "dist/Hello-ios/project.yml")).dig("targets", "Hello", "settings", "base")
      FileUtils.rm_rf(File.join(@dir, "dist"))
      base.values_at("GCC_PREPROCESSOR_DEFINITIONS", "OTHER_LDFLAGS", "ENABLE_DEBUG_DYLIB")
    end
    assert_equal [[nil, "$(inherited) -Wl,-stack_size,0x4000000", false]] * 2, settings
  end

  def test_an_ios_app_without_an_icon_has_no_asset_catalog
    skip "this computer has no XcodeGen" unless xcodegen?
    root = script_app("identifier: com.example.Hello\n")

    _, err, status = build("ios", root, host: "arm64-darwin-24")

    assert_equal 0, status, err
    refute_path_exists File.join(@dir, "dist/Hello-ios/Host/Assets.xcassets")
    assert_equal "", YAML.safe_load_file(File.join(@dir, "dist/Hello-ios/project.yml")).dig("targets", "Hello", "settings", "base",
      "ASSETCATALOG_COMPILER_APPICON_NAME")
  end

  def test_a_phones_gems_are_pure_ruby_set_up_by_bundler_with_force_ruby_platform
    pure = FakeGem.build(@gems, "pure", "1.0.0")
    linux = FakeGem.build(@gems, "dual", "2.0.0", platform: "x86_64-linux-gnu")
    source = FakeGem.build(@gems, "dual", "2.0.0")
    root = gem_project(dependencies: { "pure" => ">= 0", "dual" => ">= 0" }, locked: [pure, linux, source],
      platforms: %w[ruby arm64-darwin x86_64-linux aarch64-linux x64-mingw-ucrt])

    out, err, status = build("android", root)

    assert_equal [0, "dist/MyApp-android\n"], [status, out], err
    gems = File.join(@dir, "dist/MyApp-android/fledge/lib/ruby/gems/4.1.0+5")
    assert_path_exists File.join(gems, "gems/pure-1.0.0/lib/pure.rb")
    assert_path_exists File.join(gems, "gems/dual-2.0.0/lib/dual.rb"), "a gem with a build for Linux ships its ruby one"
    refute_path_exists File.join(gems, "gems/dual-2.0.0-x86_64-linux-gnu")
    assert_equal "#{Fledge::Bundle::SETTINGS}BUNDLE_WITHOUT: \"\"\nBUNDLE_WITH: \"\"\nBUNDLE_ONLY: \"\"\nBUNDLE_FORCE_RUBY_PLATFORM: \"true\"\n", read("dist/MyApp-android/fledge/app/.bundle/config")
    assert_equal "# Written by fledge build: what this app's program runs.\nentry = exe/my_app\ngemfile = Gemfile\n" \
      "identifier = com.example.MyApp\n", read("dist/MyApp-android/fledge/fledge.cfg")
  end

  # A gem with no extension that carries a library built for desktop
  # Linux, which its Ruby would open from fledge.zip on the phone, keeps
  # the Android app from shipping, named as a desktop's build names it.
  def test_an_android_app_whose_gem_carries_a_library_for_desktop_linux_cannot_ship
    TestReaders.need(self, :elf)
    drawn = FakeGem.build(@gems, "drawn", "1.0.0", files: { "lib/drawn.rb" => "", "lib/libdrawn.x86_64.so" => Binaries.elf(needed: %w[libc.so.6]) })
    root = gem_project(dependencies: { "drawn" => ">= 0" }, locked: [drawn], platforms: %w[ruby arm64-darwin x86_64-linux aarch64-linux x64-mingw-ucrt])

    _, err, status = build("android", root)

    assert_equal [
      1,
      [
        "fledge build: MyApp can't ship for android:",
        "fledge build:   drawn 1.0.0's lib/libdrawn.x86_64.so needs libc.so.6, which neither Android, nor Fledge's runtime, nor the " \
          "app's own native libraries provide, so the app could not load it on a phone. Build the gem so that it carries the library, " \
          "or links it statically.",
          ],
], [status, err.lines.map(&:chomp).grep_v(/\ADownloading /)]
    refute_path_exists File.join(@dir, "dist/MyApp-android")
  end

  # A gemspec that names a bare CMakeLists.txt is refused by name before
  # anything compiles, whether or not this computer has an NDK. One that
  # names a Rakefile is built (test/mobile_extensions_test.rb, and
  # test/integration/mobile_extensions_build_test.rb with a phone's runtime).
  def test_a_phone_needs_the_lockfile_to_lock_ruby_and_refuses_extensions_no_extconf_or_rakefile_builds
    native = FakeGem.build(@gems, "native", "1.0.0", extensions: ["ext/native/CMakeLists.txt"],
      files: { "ext/native/CMakeLists.txt" => "# cmake\n", "lib/native.rb" => "" })
    root = gem_project(dependencies: { "native" => ">= 0" }, locked: [native])

    _, err, status = build("android", root)
    assert_equal [1, "fledge build: Gemfile.lock locks no gems for android. Run bundle lock --add-platform ruby, then build again.\n"],
      [status, err]

    gem_project(dependencies: { "native" => ">= 0" }, locked: [native], platforms: %w[ruby arm64-darwin x86_64-linux aarch64-linux x64-mingw-ucrt])
    _, err, status = build("android", root)
    assert_equal 1, status
    assert_equal [
      "fledge build: MyApp can't ship for android:",
      "fledge build:   native 1.0.0 has an extension built by ext/native/CMakeLists.txt, and Fledge compiles for android only " \
        "extensions that an extconf.rb or a Rakefile builds (an extconf.rb may run CMake first). Leave it out of the app's android " \
        "build (gem \"native\", platforms: [...] in the Gemfile), or ask its author for an extconf.rb.",
    ], err.lines.map(&:chomp).grep_v(/\ADownloading /)
    refute_path_exists File.join(@dir, "dist/MyApp-android")
  end

  def test_a_gem_with_no_ruby_build_says_so
    linux = FakeGem.build(@gems, "binary", "1.0.0", platform: "x86_64-linux-gnu")
    root = gem_project(dependencies: { "binary" => ">= 0" }, locked: [linux], platforms: %w[ruby arm64-darwin x86_64-linux aarch64-linux x64-mingw-ucrt])

    _, err, status = build("android", root)

    assert_equal [
      1,
      "fledge build: Gemfile.lock locks no build of binary for android, only for x86_64-linux-gnu. If binary has " \
        "one, run bundle lock --add-platform ruby, then build again.\n",
], [status, err]
  end

  # Writes +files+, by path, into the project's folder +host+.
  def host_files(root, host, files)
    files.each do |path, text|
      file = File.join(root, host, path)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, text)
    end
  end

  # The files in android's host replace Fledge's at the same paths, or join
  # them, before Fledge fills its marks, and the build says which of Fledge's
  # it replaced. ios's host is not android's to check.
  def test_an_android_hosts_files_replace_fledges_and_join_them
    root = script_app("identifier: com.example.Hello\nandroid:\n  host: host/android\nios:\n  host: missing\n")
    activity = "src/main/java/org/setdef/fledge/host/MainActivity.java"
    host_files(root, "host/android", {
      activity => "// the host's own\n",
      "src/main/java/org/libsdl/app/SDLActivity.java" => "// SDL's\n",
      "build.gradle" => "applicationId = '@@APPLICATION_ID@@'\nuseLegacyPackaging = true\n",
    })

    out, err, status = build("android", root)

    assert_equal [0, "dist/Hello-android\n", "host/android replaces Fledge's build.gradle, #{activity}\n"], [status, out, err]
    assert_equal "// the host's own\n", read("dist/Hello-android", activity)
    assert_equal "// SDL's\n", read("dist/Hello-android/src/main/java/org/libsdl/app/SDLActivity.java")
    assert_equal "applicationId = 'com.example.Hello'\nuseLegacyPackaging = true\n", read("dist/Hello-android/build.gradle"),
      "Fledge fills its marks in the host's copy"
    assert_includes read("dist/Hello-android/settings.gradle"), "rootProject.name = 'Hello'", "what the host leaves is Fledge's"
    assert_path_exists File.join(@dir, "dist/Hello-android/fledge/app/main.rb")
    refute_path_exists File.join(@dir, "dist/Hello-android/fledge/app/host/android"), "the host is the project's, not the app's"
  end

  # Every app's Ruby runs on Android's main thread, whatever its kind, as
  # under ruby main.rb, and the activity shows nothing of its own.
  def test_every_android_apps_ruby_starts_on_the_main_thread_whatever_its_kind
    activities = %w[console windowed].map do |kind|
      root = script_app("identifier: com.example.Hello\nkind: #{kind}\n")
      assert_equal 0, build("android", root).last
      read("dist/Hello-android/src/main/java/org/setdef/fledge/host/MainActivity.java").tap { FileUtils.rm_rf(File.join(@dir, "dist")) }
    end

    assert_equal 1, activities.uniq.size, "the kind changes nothing"
    assert_includes activities.first, "FledgeRuby.startAppOnMainThread(this, "
    refute_match(/FledgeRuby\.startApp\(|setContentView/, activities.first)
  end

  def test_a_phones_host_must_be_a_folder_in_the_project
    root = script_app("identifier: com.example.Hello\nandroid:\n  host: host/android\n")

    _, err, status = build("android", root)

    assert_equal [1, "fledge build: #{File.join(root, 'fledge.yml')}: android's host, host/android, is not a folder in the project\n"],
      [status, err]
    refute_path_exists File.join(@dir, "dist/Hello-android")
    return if Gem.win_platform?

    FileUtils.mkdir_p([File.join(@dir, "elsewhere"), File.join(root, "host")])
    File.symlink(File.join(@dir, "elsewhere"), File.join(root, "host/android"))
    _, err, = build("android", root)
    assert_equal "fledge build: #{File.join(root, 'fledge.yml')}: android's host, host/android, is not a folder in the project\n", err
  end

  # On iOS the host's files are in place before XcodeGen writes the
  # project, so a host's project.yml is the one XcodeGen reads.
  def test_an_ios_hosts_files_are_in_place_before_xcodegen_runs
    skip "this computer has no XcodeGen" unless xcodegen?
    root = script_app("identifier: com.example.Hello\nios:\n  host: host/ios\n")
    spec = File.read(File.join(Fledge::MobileProject::TEMPLATES, "ios", "project.yml"))
    host_files(root, "host/ios", {
      "Host/main.m" => "int main(void) { return 0; }\n",
      "project.yml" => spec.sub("        OTHER_LDFLAGS:", "        FLEDGE_HOST_TEST: YES\n        OTHER_LDFLAGS:"),
    })

    out, err, status = build("ios", root, host: "arm64-darwin-24")

    assert_equal [0, "dist/Hello-ios\n", "host/ios replaces Fledge's Host/main.m, project.yml\n"], [status, out, err]
    assert_equal "int main(void) { return 0; }\n", read("dist/Hello-ios/Host/main.m")
    assert_includes read("dist/Hello-ios/Hello.xcodeproj/project.pbxproj"), "FLEDGE_HOST_TEST = YES;"
    assert_includes read("dist/Hello-ios/Hello.xcodeproj/project.pbxproj"), "PRODUCT_BUNDLE_IDENTIFIER = com.example.Hello;"
  end

  # 0.17.0's runtime is a static library, which the app links and does
  # not embed; a runtime whose Ruby is a framework is embedded too.
  def test_an_ios_app_embeds_rubys_framework_only_when_the_runtime_has_one
    skip "this computer has no XcodeGen" unless xcodegen?
    root = script_app("identifier: com.example.Hello\n")
    embed = lambda do
      assert_equal 0, build("ios", root, host: "arm64-darwin-24").last
      dependencies = YAML.safe_load_file(File.join(@dir, "dist/Hello-ios/project.yml")).dig("targets", "Hello", "dependencies")
      dependencies.find { |dependency| dependency["framework"] == "FledgeRuby.xcframework" }.fetch("embed")
    end

    assert_equal [false], [embed.call]
    FakeRuntime.write_mobile(@runtimes, Fledge::MobilePlatform.find("ios"), dynamic: true)
    assert_equal [true], [embed.call]
  end

  # A host's copy of the template from before the runtime's Ruby was a
  # framework links it without embedding it, and its app would stop as
  # it starts.
  def test_an_ios_host_that_does_not_embed_a_dynamic_ruby_is_refused
    FakeRuntime.write_mobile(@runtimes, Fledge::MobilePlatform.find("ios"), dynamic: true)
    root = script_app("identifier: com.example.Hello\nios:\n  host: host/ios\n")
    spec = File.read(File.join(Fledge::MobileProject::TEMPLATES, "ios", "project.yml"))
    host_files(root, "host/ios", { "project.yml" => spec.sub("embed: @@RUBY_EMBED@@", "embed: false") })

    _, err, status = build("ios", root, host: "arm64-darwin-24")

    assert_equal [
      1,
      "host/ios replaces Fledge's project.yml\nfledge build: project.yml links FledgeRuby.xcframework without " \
        "embedding it, and the runtime's Ruby is a framework the app must embed: give its dependency " \
        "embed: @@RUBY_EMBED@@, as Fledge's template does\n",
], [status, err]
  end

  def test_the_dependencies_mark_lists_the_apps_extensions_and_each_framework_embedded_and_not_linked
    assert_equal "", Fledge::MobileProject::IOS.dependencies(extensions: false, frameworks: [])
    assert_equal "- framework: Frameworks/fledgerubyext.etc.bundle.xcframework\n        embed: true\n        link: false",
      Fledge::MobileProject::IOS.dependencies(extensions: false, frameworks: ["fledgerubyext.etc.bundle"])
    assert_equal "- framework: FledgeExtensions.xcframework\n        embed: false\n      " \
      "- framework: Frameworks/a.xcframework\n        embed: true\n        link: false",
      Fledge::MobileProject::IOS.dependencies(extensions: true, frameworks: ["a"])
  end

  def test_the_version_code_grows_with_the_version
    assert_equal [1, 1000, 1_002_003, 2_100_000_000], %w[0.0.0 0.1.0.pre.1 1.2.3 2100.0.0].map { |version|
      Fledge::MobileProject::Android.version_code(version)
    }
    error = assert_raises(Fledge::Error) { Fledge::MobileProject::Android.version_code("1.1000.0") }
    assert_equal "Android needs a whole-number versionCode no greater than 2100000000, which Fledge makes from the version's " \
      "numbers, three digits each, and 1.1000.0 does not fit", error.message
  end

  # An Android extension built as a file goes to each ABI's jniLibs as
  # libfledgeext.FEATURE.so, and fledge.links names where a desktop has
  # its file. With nothing linked in, libfledgeext.so registers nothing,
  # and is there for a host that names it; Fledge's own loads nothing,
  # since the runtime loads it.
  def test_an_android_extension_built_as_a_file_is_a_native_library_named_for_its_feature
    project = android_project_with_library("adder/adder")

    library = File.join(project, "src/main/jniLibs/x86_64/libfledgeext.adder.adder.so")
    assert_equal "ELF adder", File.read(library)
    refute_includes File.read(File.join(project, "src/main/jniLibs/x86_64/libfledgeext.so")), "fledge_ruby_add_extension("
    assert_equal "#{FakeRuntime::ANDROID_LINKS}x86_64\tlibfledgeext.adder.adder.so\tapp/gems/adder/lib/adder/adder.so\n#{RAKE_LINKS}",
      File.read(File.join(project, "fledge/fledge.links"))
    refute_includes File.read(File.join(project, "src/main/java/org/setdef/fledge/host/MainActivity.java")), "loadLibrary"
  end

  # An extension built as a file loads only from the native libraries
  # the package installer extracts, which a build.gradle that sets
  # useLegacyPackaging = false, as Fledge's template did before 0.13.0,
  # keeps it from extracting, and so does one that sets nothing, since
  # the Android Gradle plugin's default for a minSdk of 23 or later
  # keeps them stored: a host's copy that does either is refused, naming
  # the file, the extension, and the line to set, and one that says
  # true, in any of Groovy's ways, builds.
  # (A host's build.gradle with false and no such extension builds:
  # test_an_android_hosts_files_replace_fledges_and_join_them.)
  def test_an_android_host_that_keeps_native_libraries_stored_cannot_ship_an_extension_built_as_a_file
    gradle = "android {\n    packaging {\n        jniLibs {\n            useLegacyPackaging = false\n        }\n    }\n}\n"
    error = assert_raises(Fledge::Error) { android_project_with_library("adder/adder", host: { "build.gradle" => gradle }) }

    assert_equal "Hello can't ship for android:\n  host/android/build.gradle sets useLegacyPackaging = false, so the package " \
      "installer extracts none of the app's native libraries, and adder's extension adder/adder and Ruby's own extensions and " \
      "encodings, which Ruby loads from among " \
      "them, would not load on a phone. Set useLegacyPackaging = true in its packaging { jniLibs { } } block, as Fledge's own " \
      "build.gradle does.", error.message
    refute_path_exists File.join(@dir, "dist", "Hello-android")

    log = StringIO.new
    kept = "android {\n    packagingOptions.jniLibs.useLegacyPackaging true\n}\n/* Fledge's template said\n   useLegacyPackaging = false until 0.13.0 */\n"
    assert_path_exists android_project_with_library("adder/adder", host: { "build.gradle" => kept }, log:)
    assert_equal "host/android replaces Fledge's build.gradle\n", log.string

    error = assert_raises(Fledge::Error) { android_project_with_library("adder/adder", host: { "build.gradle" => "android {\n}\n" }) }
    assert_equal "Hello can't ship for android:\n  host/android/build.gradle sets no useLegacyPackaging for its native " \
      "libraries, and for a minSdk of 23 or later the Android Gradle plugin then keeps them stored, so the package installer " \
      "extracts none of them, and adder's extension adder/adder and Ruby's own extensions and encodings, which Ruby loads from " \
      "among them, would not load on a phone. " \
      "Add useLegacyPackaging = true in a packaging { jniLibs { } } block, as Fledge's own build.gradle has it.", error.message
    refute_path_exists File.join(@dir, "dist", "Hello-android")
  end

  # Ruby's own extensions and encodings are among every Android app's
  # native libraries, so an app with no compiled gem of its own is
  # refused a host's copy that keeps them stored too; with 0.17.0's
  # runtime, which links them into its library and lists none in its
  # fledge.links, the same app builds.
  def test_an_android_host_that_keeps_native_libraries_stored_cannot_ship_rubys_own_extensions
    root = script_app("identifier: com.example.Hello\nandroid:\n  host: host/android\n")
    host_files(root, "host/android", { "build.gradle" => "android {\n    packagingOptions.jniLibs.useLegacyPackaging = false\n}\n" })

    _, err, status = build("android", root)

    assert_equal [
      1,
      "host/android replaces Fledge's build.gradle\nfledge build: Hello can't ship for android:\n" \
        "fledge build:   host/android/build.gradle sets useLegacyPackaging = false, so " \
        "the package installer extracts none of the app's native libraries, and Ruby's own extensions and encodings, which Ruby " \
        "loads from among them, would not load on a phone. Set useLegacyPackaging = true in its packaging { jniLibs { } } block, " \
        "as Fledge's own build.gradle does.\n",
], [status, err]

    FakeRuntime.write_mobile(@runtimes, Fledge::MobilePlatform.find("android"), links: false)
    out, err, status = build("android", root)

    assert_equal [0, "dist/Hello-android\n"], [status, out], err
    assert_equal RAKE_LINKS, read("dist/Hello-android/fledge/fledge.links")
  end

  # The Android Gradle plugin has a useLegacyPackaging for dex files
  # too (DexPackaging), which says nothing of native libraries: a host
  # that sets it after jniLibs', in a block or by its path, builds, and
  # one that sets it alone has set none for its native libraries, and is
  # refused.
  def test_an_android_hosts_packaging_of_dex_files_is_not_its_packaging_of_native_libraries
    block = "android {\n    packaging {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n        " \
      "dex {\n            useLegacyPackaging = false\n        }\n    }\n}\n"
    path = "android {\n    packaging.jniLibs.useLegacyPackaging = true\n    packaging.dex.useLegacyPackaging = false\n}\n"
    [block, path].each do |gradle|
      log = StringIO.new
      assert_path_exists android_project_with_library("adder/adder", host: { "build.gradle" => gradle }, log:)
      assert_equal "host/android replaces Fledge's build.gradle\n", log.string
    end

    alone = "android {\n    packaging {\n        dex {\n            useLegacyPackaging = false\n        }\n    }\n}\n"
    error = assert_raises(Fledge::Error) { android_project_with_library("adder/adder", host: { "build.gradle" => alone }) }
    assert_match(%r{\n  host/android/build\.gradle sets no useLegacyPackaging for its native libraries, }, error.message)
  end

  # The package installer extracts only a library whose name has the
  # characters isFilenameSafe takes (AOSP's ApkParsing.cpp).
  def test_an_android_extension_whose_feature_android_cannot_install_is_refused
    error = assert_raises(Fledge::Error) { android_project_with_library("my ext/ext") }

    assert_equal "the extension my ext/ext has a name Android cannot install as a native library: only letters, digits, and + , - . = _",
      error.message
  end

  # A library a gem's Rakefile builds for Ruby's ffi goes to each ABI's
  # jniLibs as libfledgeffi.GEM.PATH.so, named for its gem and its path
  # in the gem, and fledge.links names the path where the gem asks ffi
  # for it. (On iOS it is a framework, which Xcode's tools make:
  # test/ios_libraries_test.rb and the integration tests.)
  def test_an_android_library_for_ffi_that_a_rakefile_built_is_a_native_library_named_for_its_gem_and_path
    project = phone_project_with_ffi_library("android", "x86_64-linux-android", "x86_64", "ext/x86_64-linux/libllhttp-ext.so")

    name = "libfledgeffi.llhttp-ffi.ext.x86_64-linux.libllhttp-ext.so"
    assert_equal "ELF llhttp", File.read(File.join(project, "src/main/jniLibs/x86_64", name))
    assert_equal "#{FakeRuntime::ANDROID_LINKS}x86_64\t#{name}\tlib/ruby/gems/4.1.0+5/gems/llhttp-ffi-0.5.1/ext/x86_64-linux/libllhttp-ext.so\n" \
      "#{RAKE_LINKS}",
      File.read(File.join(project, "fledge/fledge.links"))
  end

  # A library whose path ends in a version, as librdkafka.so.1 would,
  # still ends in .so, which the package installer extracts.
  def test_an_android_library_for_ffi_whose_name_ends_in_a_version_ends_in_so
    project = phone_project_with_ffi_library("android", "x86_64-linux-android", "x86_64", "ext/librdkafka.so.1")

    assert_path_exists File.join(project, "src/main/jniLibs/x86_64/libfledgeffi.llhttp-ffi.ext.librdkafka.so.1.so")
  end

  # Two libraries whose names come out alike in one ABI's folder would
  # overwrite each other: refused, naming both.
  def test_an_android_library_for_ffi_named_as_another_is_refused
    error = assert_raises(Fledge::Error) do
      phone_project_with_ffi_library("android", "x86_64-linux-android", "x86_64", "ext/a.b/lib.so", "ext/a/b.lib.so")
    end

    assert_equal "llhttp-ffi's ext/a.b/lib.so and llhttp-ffi's ext/a/b.lib.so would both be libfledgeffi.llhttp-ffi.ext.a.b.lib.so " \
      "in the Android app's x86_64 libraries", error.message
  end

  # An Android library that needs a library Android offers no app, such
  # as glibc's libc.so.6 a desktop's build linked, or one nothing in the
  # app carries, would fail when Ruby opens it on the phone: the build
  # refuses it, naming the gem and each library, as a desktop's build
  # refuses a gem's file (Fledge::Linkage). One that needs only Android's
  # public libraries builds.
  def test_an_android_library_that_needs_what_no_phone_has_keeps_the_app_from_shipping
    TestReaders.need(self, :elf)
    error = assert_raises(Fledge::Error) do
      phone_project_with_ffi_library("android", "x86_64-linux-android", "x86_64", "ext/x86_64-linux/libllhttp-ext.so",
        content: Binaries.elf(needed: %w[libc.so.6 libxml2.so.2]))
    end

    assert_equal [
      "Hello can't ship for android:",
      "  llhttp-ffi's ext/x86_64-linux/libllhttp-ext.so needs libc.so.6 and libxml2.so.2, which neither Android, nor Fledge's " \
        "runtime, nor the app's own native libraries provide, so the app could not load them on a phone. Build the gem so that " \
        "it carries the libraries, or links them statically.",
    ], error.message.lines.map(&:chomp)
    refute_path_exists File.join(@dir, "dist", "Hello-android")

    project = phone_project_with_ffi_library("android", "x86_64-linux-android", "x86_64", "ext/x86_64-linux/libllhttp-ext.so",
      content: Binaries.elf(needed: %w[liblog.so libz.so libdl.so libm.so libc.so]))
    assert_path_exists File.join(project, "src/main/jniLibs/x86_64/libfledgeffi.llhttp-ffi.ext.x86_64-linux.libllhttp-ext.so")
  end

  # A compiled file a gem's package holds, which reaches the app inside
  # fledge.zip, where the gem's Ruby opens it by its path, is judged as a
  # desktop's build judges a gem's file, for the ABI of its processor:
  # one built for desktop Linux, as raylib-bindings carries one for each
  # processor, needs glibc's libraries, which no phone has. One that
  # needs only Android's libraries builds, and so does a file another
  # system's loader reads, or one fledge.links puts a native library at.
  def test_an_android_gems_compiled_file_inside_fledge_zip_is_judged_for_its_processor
    TestReaders.need(self, :elf)
    gem = "lib/ruby/gems/4.1.0+5/gems/drawn-1.0.0"
    files = {
"lib/libdrawn.x86_64.so" => Binaries.elf(needed: %w[libc.so.6]),
"lib/libdrawn.aarch64.so" => Binaries.elf(needed: %w[libc.so.6 libGLX.so.0], cpu: "aarch64"),
"lib/libdrawn.arm64.dylib" => Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib]),
"lib/linked.so" => Binaries.elf(needed: %w[libc.so.6 libxml2.so.2]),
}
    error = assert_raises(Fledge::Error) { android_project_with_gem_files(gem, "drawn 1.0.0", files, links: ["#{gem}/lib/linked.so"]) }

    assert_equal [
      "Hello can't ship for android:",
      "  drawn 1.0.0's lib/libdrawn.aarch64.so needs libc.so.6 and libGLX.so.0, which neither Android, nor Fledge's runtime, nor the " \
        "app's own native libraries provide, so the app could not load them on a phone. Build the gem so that it carries the " \
        "libraries, or links them statically.",
      "  drawn 1.0.0's lib/libdrawn.x86_64.so needs libc.so.6, which neither Android, nor Fledge's runtime, nor the app's own native " \
        "libraries provide, so the app could not load it on a phone. Build the gem so that it carries the library, or links it statically.",
    ], error.message.lines.map(&:chomp)

    project = android_project_with_gem_files(gem, "drawn 1.0.0", { "lib/libdrawn.x86_64.so" => Binaries.elf(needed: %w[libc.so]) })
    assert_path_exists File.join(project, "fledge", gem, "lib/libdrawn.x86_64.so")
  end

  # A library the project lists as its Android host's (android:
  # host_libraries), which the host's own Gradle dependencies add to the
  # APK, may be needed by a gem's compiled file inside fledge.zip and by
  # a library in jniLibs; one listed that nothing needs is refused, so
  # the list says only what is true.
  def test_an_android_library_may_need_a_library_the_host_adds
    TestReaders.need(self, :elf)
    gem = "lib/ruby/gems/4.1.0+5/gems/drawn-1.0.0"
    files = { "lib/libdrawn.x86_64.so" => Binaries.elf(needed: %w[libc.so libSDL3.so]) }
    listed = "identifier: com.example.Hello\nandroid:\n  host_libraries: [libSDL3.so, libgone.so]\n"
    error = assert_raises(Fledge::Error) { android_project_with_gem_files(gem, "drawn 1.0.0", files, config: listed) }

    assert_equal [
      "Hello can't ship for android:",
      "  fledge.yml's android: host_libraries lists libgone.so, which none of the app's native libraries, nor the gems' compiled " \
        "files, needs beyond what Android, Fledge's runtime, and the app's own native libraries provide. Remove it.",
    ], error.message.lines.map(&:chomp)

    host = "identifier: com.example.Hello\nandroid:\n  host_libraries: [libSDL3.so]\n"
    project = android_project_with_gem_files(gem, "drawn 1.0.0", files, config: host)
    assert_path_exists File.join(project, "fledge", gem, "lib/libdrawn.x86_64.so")
    FileUtils.rm_rf(File.join(@dir, "dist"))
    project = phone_project_with_ffi_library("android", "x86_64-linux-android", "x86_64", "ext/x86_64-linux/libllhttp-ext.so",
      content: Binaries.elf(needed: %w[libc.so libSDL3.so]), config: host)
    assert_path_exists File.join(project, "src/main/jniLibs/x86_64/libfledgeffi.llhttp-ffi.ext.x86_64-linux.libllhttp-ext.so")
  end

  # What every target's build of a gem left alike in its folder
  # (MobileExtensions::LeftFiles) joins the gem's files in the app, where
  # the gem's Ruby reads it as under bundle exec, and a file the build
  # rewrote takes the place of the gem's own.
  def test_the_files_a_gems_builds_left_alike_join_its_files_in_the_app
    app = Fledge::App.at(script_app("identifier: com.example.Hello\n"))
    gem = "lib/ruby/gems/4.1.0+5/gems/tabled-1.0.0"
    own = [Fledge::Entry.directory(gem), Fledge::Entry.file("#{gem}/lib/tabled.rb", "the gem's own\n")]
    left = [Fledge::Entry.file("#{gem}/data/table.txt", "from the build\n"), Fledge::Entry.file("#{gem}/lib/tabled.rb", "as the build rewrote it\n")]
    built = Fledge::MobileExtensions::Built.new(registrations: [], targets: {}, ndk: nil, stubs: [], left:, apart: {})
    runtime = File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find("android")))
    project = Fledge::MobileProject::Android.new(app:, runtime:, out: File.join(@dir, "dist"), files: own, extensions: FakeExtensions.new(built)).call

    assert_equal ["from the build\n", "as the build rewrote it\n"], %w[data/table.txt lib/tabled.rb].map { |path| File.read(File.join(project, "fledge", gem, path)) }
  end

  # What each ABI's build of a gem left for itself
  # (MobileExtensions::LeftFiles.apart) is in fledge.zip under
  # .fledge-abi/ABI/, listed in fledge.files, from which the runtime
  # moves the app's own ABI's copy to the path as the app starts; the
  # gem's own file stays at the path for an ABI whose build left it be.
  def test_what_each_abis_build_left_for_itself_is_carried_for_that_abi
    app = Fledge::App.at(script_app("identifier: com.example.Hello\n"))
    gem = "lib/ruby/gems/4.1.0+5/gems/tabled-1.0.0"
    own = [Fledge::Entry.directory(gem), Fledge::Entry.file("#{gem}/data/arch.txt", "the gem's own\n")]
    targets = { "aarch64-linux-android" => "arm64-v8a", "x86_64-linux-android" => "x86_64" }.to_h do |name, abi|
      target = Fledge::MobileExtensions::Target.new(name:, root: @dir, arch_dir: @dir, libdir: @dir, environment: {}, abi:)
      [name, Fledge::MobileExtensions::TargetBuild.new(target:, archives: [], flags: [], cxx: false, libraries: [], ffi_libraries: [])]
    end
    apart = { "x86_64-linux-android" => [Fledge::Entry.file("#{gem}/data/arch.txt", "x86_64\n"), Fledge::Entry.file("#{gem}/ext/Makefile", "CC = x86_64\n")] }
    built = Fledge::MobileExtensions::Built.new(registrations: [], targets:, ndk: nil, stubs: [], left: [], apart:)
    runtime = File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find("android")))
    project = Fledge::MobileProject::Android.new(app:, runtime:, out: File.join(@dir, "dist"), files: own, extensions: FakeExtensions.new(built)).call
    root = File.join(project, "fledge")

    assert_equal "x86_64\t#{gem}/data/arch.txt\nx86_64\t#{gem}/ext/Makefile\n", File.read(File.join(root, "fledge.files"))
    assert_equal ["x86_64\n", "CC = x86_64\n"], %w[data/arch.txt ext/Makefile].map { |path| File.read(File.join(root, ".fledge-abi/x86_64", gem, path)) }
    assert_equal "the gem's own\n", File.read(File.join(root, gem, "data/arch.txt"))
    refute_path_exists File.join(root, ".fledge-abi/arm64-v8a")
  end

  # Writes +phone+'s project for a script app whose one gem's Rakefile
  # built a library for ffi, each of +files+ in llhttp-ffi 0.5.1, holding
  # +content+, for the target +name+ (+abi+ on Android), and returns its
  # folder.
  private def phone_project_with_ffi_library(phone, name, abi, *files, content: "ELF llhttp", config: "identifier: com.example.Hello\n")
    app = Fledge::App.at(script_app(config))
    shared = File.join(@dir, "llhttp.so")
    File.binwrite(shared, content)
    target = Fledge::MobileExtensions::Target.new(name:, root: @dir, arch_dir: @dir, libdir: @dir, environment: {}, abi:)
    libraries = files.map do |file|
      Fledge::MobileExtensions::FfiLibrary.new(gem: "llhttp-ffi", file:, path: shared, links: ["lib/ruby/gems/4.1.0+5/gems/llhttp-ffi-0.5.1/#{file}"])
    end
    build = Fledge::MobileExtensions::TargetBuild.new(target:, archives: [], flags: [], cxx: false, libraries: [], ffi_libraries: libraries)
    built = Fledge::MobileExtensions::Built.new(registrations: [], targets: { target.name => build }, ndk: nil, stubs: [], left: [], apart: {})
    runtime = File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(phone)))
    project = (phone == "ios") ? Fledge::MobileProject::IOS : Fledge::MobileProject::Android
    project.new(app:, runtime:, out: File.join(@dir, "dist"), extensions: FakeExtensions.new(built)).call
  end

  # Writes an Android project for a script app whose one gem, +label+,
  # is in +folder+ of the Ruby root with +files+ (each path in the gem
  # and its content), and whose runtime's fledge.links names each of
  # +links+, and returns its folder.
  private def android_project_with_gem_files(folder, label, files, links: [], config: "identifier: com.example.Hello\n")
    app = Fledge::App.at(script_app(config))
    entries = [Fledge::Entry.directory(folder), *files.map { |path, content| Fledge::Entry.file("#{folder}/#{path}", content) }]
    runtime = File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find("android")))
    unless links.empty?
      runtime = File.join(@dir, "linked", File.basename(runtime))
      FileUtils.mkdir_p(File.dirname(runtime))
      FakeRuntime.write_mobile(File.dirname(runtime), Fledge::MobilePlatform.find("android"),
        more_links: links.map { |link| "x86_64\tlibfledgeffi.linked.so\t#{link}\n" }.join)
    end
    Fledge::MobileProject::Android.new(app:, runtime:, out: File.join(@dir, "dist"), files: entries, gem_folders: { folder => label }).call
  end

  # Writes an Android project for a script app whose one extension,
  # +feature+, was built as a file for x86_64, with +host+'s files, by
  # path, in its host/android, when it has any, saying to +log+ what it
  # says, and returns its folder.
  private def android_project_with_library(feature, host: {}, log: nil)
    config = "identifier: com.example.Hello\n"
    config += "android:\n  host: host/android\n" unless host.empty?
    root = script_app(config)
    host_files(root, "host/android", host)
    app = Fledge::App.at(root)
    shared = File.join(@dir, "adder.so")
    File.write(shared, "ELF adder")
    target = Fledge::MobileExtensions::Target.new(name: "x86_64-linux-android", root: @dir, arch_dir: @dir, libdir: @dir, environment: {}, abi: "x86_64")
    library = Fledge::MobileExtensions::Library.new(gem: "adder", feature:, path: shared, flags: [], links: ["app/gems/adder/lib/#{feature}.so"])
    build = Fledge::MobileExtensions::TargetBuild.new(target:, archives: [], flags: [], cxx: false, libraries: [library], ffi_libraries: [])
    built = Fledge::MobileExtensions::Built.new(registrations: [], targets: { target.name => build }, ndk: nil, stubs: [], left: [], apart: {})
    runtime = File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find("android")))
    Fledge::MobileProject::Android.new(app:, runtime:, out: File.join(@dir, "dist"), extensions: FakeExtensions.new(built), log:).call
  end

  private def xcodegen?
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |folder| File.executable?(File.join(folder, "xcodegen")) }
  end
end
