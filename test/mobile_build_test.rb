# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"
require_relative "support/loopback_server"
require "stringio"
require "yaml"

# fledge build ios and fledge build android (ADR 012), through real
# streams, with fake mobile runtimes shaped as ADR 011 describes them,
# real .gem files served at the lockfile's remote, and, for iOS, the real
# XcodeGen where this computer has it.
class MobileBuildTest < Minitest::Test
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
    status = Dir.chdir(@dir) { Fledge::CLI::Build.new(out:, err:, env:, host: Gem::Platform.new(host), ruby:).call(argv) }
    [out.string, err.string, status]
  end

  # A phone's Ruby is the minor version that runs fledge build too (ADR
  # 028, section 3); the fake runtimes are Ruby 4.0.9.
  def test_a_phone_project_on_another_ruby_minor_than_the_runtimes_fails
    script_app("identifier: com.example.Hello\n")
    out, err, status = build("android", "hello", ruby: "4.1.0")

    assert_equal [1, ""], [status, out]
    assert_includes err, "fledge build: You are running Ruby 4.1.0, and Fledge #{Fledge::VERSION}'s runtime for android is Ruby 4.0.9.\n"
    refute_path_exists File.join(@dir, "dist/Hello-android")
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
    assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = main.rb\nidentifier = com.example.BobsApp\n",
      File.read(File.join(project, "fledge/fledge.cfg"))
    assert_equal "puts 'hi'\n", File.read(File.join(project, "fledge/app/main.rb"))
    assert_equal "# stdlib\n", File.read(File.join(project, "fledge/lib/ruby/stdlib.rb")), "the runtime's Ruby is the asset's"
    assert_equal "certificates\n", File.read(File.join(project, "fledge/libexec/cert.pem"))
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
    gems = File.join(@dir, "dist/MyApp-android/fledge/lib/ruby/gems/4.0.0")
    assert_path_exists File.join(gems, "gems/pure-1.0.0/lib/pure.rb")
    assert_path_exists File.join(gems, "gems/dual-2.0.0/lib/dual.rb"), "a gem with a build for Linux ships its ruby one"
    refute_path_exists File.join(gems, "gems/dual-2.0.0-x86_64-linux-gnu")
    assert_equal "#{Fledge::Bundle::SETTINGS}BUNDLE_WITHOUT: \"development:test\"\nBUNDLE_FORCE_RUBY_PLATFORM: \"true\"\n", read("dist/MyApp-android/fledge/app/.bundle/config")
    assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = exe/my_app\ngemfile = Gemfile\n" \
      "identifier = com.example.MyApp\n", read("dist/MyApp-android/fledge/fledge.cfg")
  end

  def test_a_phone_needs_the_lockfile_to_lock_ruby_and_refuses_extensions_mkmf_does_not_build
    native = FakeGem.build(@gems, "native", "1.0.0", extensions: ["ext/native/Rakefile"],
      files: { "ext/native/Rakefile" => "# rake\n", "lib/native.rb" => "" })
    root = gem_project(dependencies: { "native" => ">= 0" }, locked: [native])

    _, err, status = build("android", root)
    assert_equal [1, "fledge build: Gemfile.lock locks no gems for android. Run bundle lock --add-platform ruby, then build again.\n"],
      [status, err]

    gem_project(dependencies: { "native" => ">= 0" }, locked: [native], platforms: %w[ruby arm64-darwin x86_64-linux aarch64-linux x64-mingw-ucrt])
    _, err, status = build("android", root)
    assert_equal 1, status
    assert_equal [
      "fledge build: MyApp can't ship for android:",
      "fledge build:   native 1.0.0 has an extension built by ext/native/Rakefile, and Fledge compiles for android only extensions " \
        "that an extconf.rb builds, with mkmf, as Ruby's own tools do (an extconf.rb may run CMake first). Leave it out of the app's android build (gem \"native\", " \
        "platforms: [...] in the Gemfile), or ask its author for an extconf.rb.",
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

  # ADR 025, section 5: the files in android's host replace Fledge's at
  # the same paths, or join them, before Fledge fills its marks, and the
  # build says which of Fledge's it replaced. ios's host is not android's
  # to check.
  def test_an_android_hosts_files_replace_fledges_and_join_them
    root = script_app("identifier: com.example.Hello\nandroid:\n  host: host/android\nios:\n  host: missing\n")
    activity = "src/main/java/org/setdef/fledge/host/MainActivity.java"
    host_files(root, "host/android", {
      activity => "// the host's own\n",
      "src/main/java/org/libsdl/app/SDLActivity.java" => "// SDL's\n",
      "build.gradle" => "applicationId = '@@APPLICATION_ID@@'\n",
    })

    out, err, status = build("android", root)

    assert_equal [0, "dist/Hello-android\n", "host/android replaces Fledge's build.gradle, #{activity}\n"], [status, out, err]
    assert_equal "// the host's own\n", read("dist/Hello-android", activity)
    assert_equal "// SDL's\n", read("dist/Hello-android/src/main/java/org/libsdl/app/SDLActivity.java")
    assert_equal "applicationId = 'com.example.Hello'\n", read("dist/Hello-android/build.gradle"), "Fledge fills its marks in the host's copy"
    assert_includes read("dist/Hello-android/settings.gradle"), "rootProject.name = 'Hello'", "what the host leaves is Fledge's"
    assert_path_exists File.join(@dir, "dist/Hello-android/fledge/app/main.rb")
    refute_path_exists File.join(@dir, "dist/Hello-android/fledge/app/host/android"), "the host is the project's, not the app's"
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
      "project.yml" => spec.sub("        OTHER_LDFLAGS:", "        ENABLE_DEBUG_DYLIB: NO\n        OTHER_LDFLAGS:"),
    })

    out, err, status = build("ios", root, host: "arm64-darwin-24")

    assert_equal [0, "dist/Hello-ios\n", "host/ios replaces Fledge's Host/main.m, project.yml\n"], [status, out, err]
    assert_equal "int main(void) { return 0; }\n", read("dist/Hello-ios/Host/main.m")
    assert_includes read("dist/Hello-ios/Hello.xcodeproj/project.pbxproj"), "ENABLE_DEBUG_DYLIB = NO;"
    assert_includes read("dist/Hello-ios/Hello.xcodeproj/project.pbxproj"), "PRODUCT_BUNDLE_IDENTIFIER = com.example.Hello;"
  end

  def test_the_version_code_grows_with_the_version
    assert_equal [1, 1000, 1_002_003, 2_100_000_000], %w[0.0.0 0.1.0.pre.1 1.2.3 2100.0.0].map { |version|
      Fledge::MobileProject::Android.version_code(version)
    }
    error = assert_raises(Fledge::Error) { Fledge::MobileProject::Android.version_code("1.1000.0") }
    assert_equal "Android needs a whole-number versionCode no greater than 2100000000, which Fledge makes from the version's " \
      "numbers, three digits each, and 1.1000.0 does not fit", error.message
  end

  private def xcodegen?
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |folder| File.executable?(File.join(folder, "xcodegen")) }
  end
end
