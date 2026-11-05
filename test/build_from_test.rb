# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"
require "stringio"

# fledge build --from APP (ADR 032, section 2), through real streams: an
# app built by fledge build from a fake runtime, with gems from folders
# inside and outside its project, and a second project built from it.
class BuildFromTest < Minitest::Test
  LINUX = "x86_64-linux"
  PLATFORMS = %w[arm64-darwin x64-mingw-ucrt aarch64-mingw-ucrt x86_64-linux aarch64-linux x86_64-linux-musl aarch64-linux-musl].freeze

  def setup
    @dir = File.realpath(Dir.mktmpdir)
    @runtimes = File.join(@dir, "runtimes")
    FileUtils.mkdir_p(@runtimes)
    Fledge::Platform.names.each { |name| FakeRuntime.write(@runtimes, Fledge::Platform.find(name)) }
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def build(*argv, host: LINUX, env: { "FLEDGE_RUNTIME_DIR" => @runtimes })
    out = StringIO.new
    err = StringIO.new
    status = Dir.chdir(@dir) { Fledge::CLI::Build.new(out:, err:, env:, host: Gem::Platform.new(host)).call(argv) }
    [out.string, err.string, status]
  end

  # A gem in +folder+ whose lib/NAME.rb defines +body+.
  def path_gem(folder, name)
    FileUtils.mkdir_p(File.join(folder, "lib"))
    File.write(File.join(folder, "#{name}.gemspec"),
      "Gem::Specification.new { |s| s.name = #{name.inspect}; s.version = '1.0'; s.summary = 'x'; s.authors = ['x']; " \
        "s.files = ['lib/#{name}.rb'] }\n")
    File.write(File.join(folder, "lib", "#{name}.rb"), "# #{name}\n")
  end

  # The project of the app others are built from: Player, whose Gemfile
  # takes greeter from a folder inside it and elsewhere from one beside
  # it, and whose fledge.yml adds +config+.
  def player(config = "")
    root = FakeApp.write(@dir, "player")
    path_gem(File.join(root, "vendor", "greeter"), "greeter")
    path_gem(File.join(@dir, "elsewhere"), "elsewhere")
    File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n\ngem \"greeter\", path: \"vendor/greeter\"\ngem \"elsewhere\", path: \"../elsewhere\"\n")
    File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
      PATH
        remote: ../elsewhere
        specs:
          elsewhere (1.0)

      PATH
        remote: vendor/greeter
        specs:
          greeter (1.0)

      GEM
        remote: https://rubygems.org/
        specs:

      PLATFORMS
      #{PLATFORMS.sort.map { |platform| "  #{platform}" }.join("\n")}

      DEPENDENCIES
        elsewhere!
        greeter!

      CHECKSUMS
        elsewhere (1.0)
        greeter (1.0)

      BUNDLED WITH
        4.0.20
    LOCK
    File.write(File.join(root, "fledge.yml"), "name: Player\nversion: \"9.9\"\npublisher: Player Inc.\n#{config}")
    root
  end

  # A project with no gems of its own, which fledge.yml names Game.
  def game(config = "")
    root = FakeApp.write(@dir, "game")
    File.write(File.join(root, "main.rb"), "require \"greeter\"\nputs 'game'\n")
    FileUtils.mkdir_p(File.join(root, "assets"))
    File.write(File.join(root, "assets", "level.txt"), "1\n")
    File.write(File.join(root, "fledge.yml"), "name: Game\n#{config}")
    root
  end

  # Builds Player for +host+ and returns its folder.
  def built_player(config = "", host: LINUX)
    player(config)
    _, err, status = build("-o", "players", "player", host:)
    assert_equal [0, ""], [status, err]
    File.join(@dir, "players", "Player-#{Fledge::Platform.local(Gem::Platform.new(host))}")
  end

  def files(folder)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: folder).reject { |path| File.basename(path) == "." }.sort
  end

  # The new app is the old one copied: the runtime and the gems Bundler
  # sets up stay, the project is the new one's, and Bundler gets the old
  # project's Gemfile, lockfile, settings, and the gems kept in its folder.
  def test_an_app_built_from_another_keeps_its_runtime_and_gems_and_runs_the_new_project
    from = built_player
    game

    out, err, status = build("--from", from, "game")

    assert_equal [0, "", "dist/Game-x86_64-linux.tar.gz\n"], [status, err, out]
    folder = File.join(@dir, "dist", "Game-x86_64-linux")
    app = files(File.join(folder, "app"))
    assert_equal %w[
      .bundle
      .bundle/config
      Gemfile
      Gemfile.lock
      assets
      assets/level.txt
      fledge.yml
      main.rb
      vendor
      vendor/cache
      vendor/cache/elsewhere
      vendor/cache/elsewhere/elsewhere.gemspec
      vendor/cache/elsewhere/lib
      vendor/cache/elsewhere/lib/elsewhere.rb
      vendor/greeter
      vendor/greeter/greeter.gemspec
      vendor/greeter/lib
      vendor/greeter/lib/greeter.rb
], app
    assert_equal File.read(File.join(from, "app", "Gemfile.lock")), File.read(File.join(folder, "app", "Gemfile.lock"))
    assert_equal File.read(File.join(from, "app", ".bundle", "config")), File.read(File.join(folder, "app", ".bundle", "config"))
    assert_equal "require \"greeter\"\nputs 'game'\n", File.read(File.join(folder, "app", "main.rb"))
    assert_equal files(from).reject { |path| path.start_with?("app/") || path == "Player" }.sort,
      files(folder).reject { |path| path.start_with?("app/") || path == "Game" }.sort
    assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Game"))
    assert File.executable?(File.join(folder, "Game")) unless Gem.win_platform? # Windows knows a program by its extension
    assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\n" \
      "entry = main.rb\ngemfile = Gemfile\n", File.read(File.join(folder, "fledge.cfg"))
    assert_path_exists File.join(@dir, "dist", "Game-x86_64-linux.tar.gz.sha256")
  end

  # The new app's gems are the old one's, and so are the libraries they
  # load from a Linux distribution, which its launcher looks for (ADR 030).
  def test_the_system_libraries_the_gems_load_come_along
    from = built_player
    File.write(File.join(from, "fledge.cfg"), "system_libraries = libz.so.1\n", mode: "a")
    game

    _, err, status = build("--from", from, "game")

    assert_equal [0, ""], [status, err]
    assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\n" \
      "entry = main.rb\ngemfile = Gemfile\nsystem_libraries = libz.so.1\n", File.read(File.join(@dir, "dist", "Game-x86_64-linux", "fledge.cfg"))
  end

  # Nothing of the old app's identity comes along: a windowed app's
  # desktop entry and icons are the new app's alone.
  def test_the_new_app_has_its_own_identity_and_none_of_the_old_ones
    FakeRuntime.icons(player("kind: windowed\nidentifier: com.example.Player\ninstallers: []\nicon: art\n"), "art")
    _, err, status = build("-o", "players", "player")
    assert_equal [0, ""], [status, err]
    from = File.join(@dir, "players", "Player-x86_64-linux")
    assert_path_exists File.join(from, "share/icons/hicolor/512x512/apps/com.example.Player.png")
    game("kind: windowed\nidentifier: com.example.Game\ninstallers: []\n")

    _, err, status = build("--from", from, "game")

    assert_equal [0, ""], [status, err]
    folder = File.join(@dir, "dist", "Game-x86_64-linux")
    refute_path_exists File.join(folder, "com.example.Player.desktop")
    refute_path_exists File.join(folder, "share")
    assert_includes File.read(File.join(folder, "com.example.Game.desktop")), "Name=Game\n"
    assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\n" \
      "entry = main.rb\ngemfile = Gemfile\nidentifier = com.example.Game\n", File.read(File.join(folder, "fledge.cfg"))
  end

  # On macOS a windowed app is its bundle, which --from takes as APP too,
  # and the new bundle is written and sealed again with the system's own
  # plutil and codesign.
  def test_on_macos_the_new_bundle_has_its_own_info_plist_and_seal
    skip "codesign and plutil are macOS's" unless RUBY_PLATFORM.include?("darwin")
    FakeRuntime.write(@runtimes, Fledge::Platform.find("arm64-darwin"), launcher: File.binread("/usr/bin/true"))
    from = built_player("kind: windowed\nidentifier: com.example.Player\ninstallers: []\n", host: "arm64-darwin-25")
    game("kind: windowed\nidentifier: com.example.Game\ninstallers: []\n")

    _, err, status = build("--from", File.join(from, "Player.app"), "game", host: "arm64-darwin-25")

    assert_equal [0, ""], [status, err]
    bundle = File.join(@dir, "dist", "Game-arm64-darwin", "Game.app")
    assert_equal ["Game.app"], Dir.children(File.dirname(bundle))
    plist, = Open3.capture2("plutil", "-extract", "CFBundleIdentifier", "raw", "-o", "-", File.join(bundle, "Contents", "Info.plist"))
    assert_equal "com.example.Game\n", plist
    _, verify, = Open3.capture3("codesign", "--verify", "--deep", "--strict", "--verbose=2", bundle)
    assert_includes verify, "valid on disk"
    assert_path_exists File.join(bundle, "Contents", "Resources", "app", "vendor", "greeter", "lib", "greeter.rb")
  end

  # A console app built from a windowed one on macOS takes the bundle's
  # program, signed again ad hoc so that it carries no seal of the old
  # app's.
  def test_on_macos_a_console_app_from_a_bundle_carries_none_of_its_signature
    skip "codesign is macOS's" unless RUBY_PLATFORM.include?("darwin")
    FakeRuntime.write(@runtimes, Fledge::Platform.find("arm64-darwin"), launcher: File.binread("/usr/bin/true"))
    from = built_player("kind: windowed\nidentifier: com.example.Player\ninstallers: []\n", host: "arm64-darwin-25")
    game
    FileUtils.rm_f(File.join(@runtimes, Fledge::Runtimes.file_name(Fledge::Platform.find("arm64-darwin"))))

    _, err, status = build("--from", from, "game", host: "arm64-darwin-25")

    assert_equal [0, ""], [status, err]
    _, info, = Open3.capture3("codesign", "--display", "--verbose=2", File.join(@dir, "dist", "Game-arm64-darwin", "Game"))
    refute_includes info, "com.example.Player"
  end

  # An app built from another builds no gems: one that has its own is
  # built with fledge build, and nothing --from takes from the old app may
  # be replaced by the project's.
  def test_a_project_with_gems_or_files_the_old_app_provides_fails
    from = built_player
    {
      "Gemfile" => "--from builds no gems: build this project with fledge build",
      "gems.rb" => "--from builds no gems: build this project with fledge build",
      "game.gemspec" => "--from builds no gems: build this project with fledge build",
      "Gemfile.lock" => "#{File.join(@dir, 'game')} holds Gemfile.lock, which --from takes from #{from}. Remove it, or build with fledge build.",
      "vendor/greeter/x.rb" => "#{File.join(@dir, 'game')} holds vendor/greeter, which --from takes from #{from}. Remove it, or build with fledge build.",
    }.each do |file, message|
      root = game
      FileUtils.mkdir_p(File.dirname(File.join(root, file)))
      File.write(File.join(root, file), file.end_with?(".gemspec") ? "Gem::Specification.new { |s| s.name = 'game' }\n" : "")
      File.write(File.join(root, "Gemfile"), "gemspec\n") if file.end_with?(".gemspec")

      out, err, status = build("--from", from, "game")

      assert_equal [1, "", "fledge build: #{message}\n"], [status, out, err], file
      FileUtils.rm_rf(root)
    end
  end

  # programs, linux, ios, and android change the runtime or the gems.
  def test_fledge_yml_keys_that_change_the_runtime_or_gems_fail
    from = built_player
    {
      "programs:\n  - path: main.rb\n" => "programs",
      "linux:\n  system_libraries: [libz.so.1]\n" => "linux: system_libraries",
    }.each do |config, key|
      FileUtils.rm_rf(File.join(@dir, "game"))
      game(config)

      _, err, status = build("--from", from, "game")

      assert_equal [
        1,
        "fledge build: #{File.join(@dir, 'game', 'fledge.yml')} has #{key}, which changes the runtime or the gems, " \
          "and --from keeps #{from}'s. Build this project with fledge build.\n",
], [status, err]
    end
  end

  # An app whose own project is a gem (Gemfile's gemspec) has no project
  # to replace without taking its gem away.
  def test_an_app_whose_project_is_its_own_gem_cannot_be_built_from
    root = player
    File.write(File.join(root, "Gemfile.lock"), File.read(File.join(root, "Gemfile.lock")).sub("PATH\n  remote: vendor/greeter", "PATH\n  remote: ."))
    File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n\ngem \"greeter\", path: \".\"\ngem \"elsewhere\", path: \"../elsewhere\"\n")
    File.write(File.join(root, "greeter.gemspec"), File.read(File.join(root, "vendor", "greeter", "greeter.gemspec")))
    FileUtils.mkdir_p(File.join(root, "lib"))
    File.write(File.join(root, "lib", "greeter.rb"), "")
    _, err, status = build("-o", "players", "player")
    assert_equal [0, ""], [status, err]
    game

    _, err, status = build("--from", "players/Player-x86_64-linux", "game")

    assert_equal [
      1,
      "fledge build: players/Player-x86_64-linux's Gemfile.lock takes greeter from its project's own folder, " \
        "which --from replaces. Build this project with fledge build.\n",
], [status, err]
  end

  # What --from refuses before it reads the project is a usage error: an
  # APP Fledge did not build, built by another release, or for another
  # system (ADR 032, sections 2 and 6).
  def test_an_app_fledge_did_not_build_or_built_elsewhere_is_a_usage_error
    from = built_player
    game
    other = File.join(@dir, "other")
    FileUtils.mkdir_p(other)
    config = File.join(from, "fledge.cfg")
    text = File.read(config)
    {
      ["--from", "nowhere", "game"] => "--from nowhere is not a folder. Give it the folder of an app fledge build wrote, such as dist/NAME-PLATFORM.",
      ["--from", "other", "game"] => "--from other is not an app fledge build wrote: it has no fledge.cfg",
      ["--from", from, "game", { host: "aarch64-linux" }] => "--from #{from} is an app for x86_64-linux, and this computer builds for " \
        "aarch64-linux. Build from an app for this computer.",
      ["--from", from, "ios", "game"] => "--from builds for this computer; a phone's project is written with fledge build ios or android",
      ["--from"] => "--from needs an APP",
      ["--from="] => "--from needs an APP",
    }.each do |argv, message|
      options = argv.last.is_a?(Hash) ? argv.pop : {}
      error = assert_raises(Fledge::UsageError, argv.inspect) { build(*argv, **options) }
      assert_equal message, error.message, argv.inspect
    end

    File.write(config, text.sub("fledge build #{Fledge::VERSION} ", "fledge build 0.4.0 "))
    error = assert_raises(Fledge::UsageError) { build("--from=#{from}", "game") }
    assert_equal "--from #{from} was built by Fledge 0.4.0, and this is Fledge #{Fledge::VERSION}. " \
      "Build from an app this Fledge built.", error.message

    File.write(config, text.sub("fledge build #{Fledge::VERSION} for x86_64-linux", "fledge build"))
    error = assert_raises(Fledge::UsageError) { build("--from", from, "game") }
    assert_equal "--from #{from} was built by an earlier Fledge, and this is Fledge #{Fledge::VERSION}. " \
      "Build from an app this Fledge built.", error.message
  end

  # A folder of no runtimes, so that none is at hand.
  def no_runtime
    folder = File.join(@dir, "no runtimes")
    FileUtils.mkdir_p(folder)
    { "FLEDGE_RUNTIME_DIR" => folder }
  end

  # build_tools (ADR 032, section 4): the app carries the runtime's tools,
  # and --from takes them from it when no runtime is at hand. The new app
  # keeps them only when its own fledge.yml asks for them too; an app
  # that does not ask carries none.
  def test_an_app_with_build_tools_carries_them_and_is_built_from_with_no_runtime
    FakeRuntime.write(@runtimes, Fledge::Platform.find(LINUX), extra: [Fledge::Entry.file("tools/appimage-runtime", "AppImage runtime", mode: 0o755)])
    refute_path_exists File.join(built_player, "tools")
    FileUtils.rm_rf(File.join(@dir, "player"))
    from = built_player("build_tools: true\n")
    assert_equal ["appimage-runtime"], Dir.children(File.join(from, "tools"))
    game

    _, err, status = build("--from", from, "game", env: no_runtime)

    assert_equal [0, ""], [status, err]
    folder = File.join(@dir, "dist", "Game-x86_64-linux")
    refute_path_exists File.join(folder, "tools")
    assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Game"))
    File.write(File.join(@dir, "game", "fledge.yml"), "name: Game\nbuild_tools: true\n")

    _, err, status = build("--from", from, "game", env: no_runtime)

    assert_equal [0, ""], [status, err]
    assert_equal "AppImage runtime", File.read(File.join(folder, "tools", "appimage-runtime"))
    assert File.executable?(File.join(folder, "tools", "appimage-runtime")) unless Gem.win_platform?
  end

  # A program named as the tools folder would collide with it.
  def test_a_program_named_tools_collides_with_the_tools_it_carries
    player("build_tools: true\nname: tools\n")
    _, err, status = build("-o", "players", "player")
    assert_equal [1, "fledge build: an app named tools would collide with the tools it carries. Give it another name.\n"], [status, err]
  end

  # On Windows the app carries the runtime's launchers, rcedit, and NSIS,
  # but not llvm-readobj, which reads compiled gems, and --from builds
  # none; with them, a Windows app is built from it with no runtime.
  def test_on_windows_an_app_with_build_tools_is_built_from_with_no_runtime
    skip "a Windows app is built on Windows, with the real runtime's launchers and rcedit" unless Gem.win_platform? && FakeRuntime.windows
    host = Fledge::Platform.local.name
    from = built_player("build_tools: true\n", host:)
    assert_equal %w[launcher.exe launcherw.exe rcedit.exe], Dir.children(File.join(from, "tools")).sort
    game("kind: windowed\nidentifier: com.example.Game\ninstallers: []\n")

    _, err, status = build("--from", from, "game", host:, env: no_runtime)

    assert_equal [0, ""], [status, err]
    folder = File.join(@dir, "dist", "Game-#{host}")
    assert_path_exists File.join(folder, "Game.exe")
    refute_path_exists File.join(folder, "tools")
  end

  # Windows' programs carry their app's identity in their resources, so
  # a Windows app built from another takes fresh launchers, and rcedit,
  # from the runtime, which no app holds yet, and downloads nothing.
  def test_on_windows_the_runtime_must_be_on_this_computer
    from = File.join(@dir, "Player-x64-mingw-ucrt")
    FileUtils.mkdir_p(File.join(from, "app"))
    File.write(File.join(from, "Player.exe"), "MZ")
    File.write(File.join(from, "fledge.cfg"),
      "# Written by fledge build #{Fledge::VERSION} for x64-mingw-ucrt: what this app's program runs (ADR 005).\nentry = main.rb\n")
    game
    cache = File.join(@dir, "cache")

    out, err, status = build("--from", from, "game", host: "x64-mingw-ucrt", env: { "XDG_CACHE_HOME" => cache })

    assert_equal [1, ""], [status, out]
    assert_equal "fledge build: --from takes a Windows app's launchers and rcedit from the tools folder of an app built with build_tools: true, " \
      "which #{from} has not, or else from Fledge #{Fledge::VERSION}'s runtime for x64-mingw-ucrt, which this computer has not: " \
      "put #{Fledge::Runtimes.file_name(Fledge::Platform.find('x64-mingw-ucrt'))} in FLEDGE_RUNTIME_DIR or #{File.join(cache, 'fledge', 'runtimes')}.\n", err
    refute_path_exists File.join(@dir, "dist", "Game-x64-mingw-ucrt")
  end
end
