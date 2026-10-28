# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/parity"
require_relative "support/disk_images"
require "json"
require "open3"
require "stringio"

# examples/hello and examples/my_cool_app, built by fledge build from a
# real runtime for this computer, unpacked by the system's own tool (tar,
# or Expand-Archive on Windows), and run in a clean and in a hostile
# environment. Building my_cool_app downloads its gems from RubyGems.org.
# .github/scripts/deliver.sh and deliver.ps1 run the same checks on fresh
# computers with no Ruby; this test runs them wherever a runtime is.
#
# The runtime comes from FLEDGE_RUNTIME_DIR, or from tmp/runtime, where
# rake runtime writes it. Without one the test skips, unless
# FLEDGE_REQUIRE_RUNTIME is set, as CI sets it on every platform with a
# runtime, so a missing runtime there fails instead of passing silently.
class BuiltAppTest < Minitest::Test
  HELLO = File.expand_path("../examples/hello", __dir__)
  MY_COOL_APP = File.expand_path("../examples/my_cool_app", __dir__)
  WINDOWED_APP = File.expand_path("../examples/windowed_app", __dir__)
  PROBE = File.expand_path("fixtures/parity", __dir__)
  EXE = File.expand_path("../exe/fledge", __dir__)
  LIB = File.expand_path("../lib", __dir__)

  def setup
    @platform = Fledge::Platform.local
    @runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
    return if File.file?(File.join(@runtimes, Fledge::Runtimes.file_name(@platform)))

    message = "no #{Fledge::Runtimes.file_name(@platform)} in #{@runtimes}; run bundle exec rake runtime"
    flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip message
  rescue Fledge::Error => e
    flunk e.message if ENV["FLEDGE_REQUIRE_RUNTIME"]
    skip e.message
  end

  def expected
    "Hello from Ruby 4.0.9 on #{expected_platform}\n"
  end

  # RUBY_PLATFORM as rv-ruby reports it: macOS builds carry the Darwin
  # version they were built for, macOS 14's.
  def expected_platform
    (@platform.name == "arm64-darwin") ? "arm64-darwin23" : @platform.name
  end

  # What examples/my_cool_app prints: the versions of i18n and sqlite3 its
  # Gemfile.lock locks, and the SQLite that sqlite3 carries.
  def my_cool_app_line
    lock = File.read(File.join(MY_COOL_APP, "Gemfile.lock"))
    i18n = lock[/^    i18n \(([^)]+)\)$/, 1]
    sqlite3 = lock[/^    sqlite3 \(([\d.]+)-/, 1]
    /\AMyCoolApp 0\.1\.0 says hello through i18n #{Regexp.escape(i18n.to_s)} and sqlite3 #{Regexp.escape(sqlite3.to_s)} \(SQLite 3\.\d+\.\d+\)\n\z/
  end

  # One build of each app serves every test: building takes seconds.
  def app = built(HELLO)

  def my_cool_app = built(MY_COOL_APP)

  def probe = built(PROBE)

  # The probe as a gem-shaped app's program (Parity.gem_probe), run with
  # Bundler as bundle exec would.
  def bundled_probe
    self.class.built[:bundled_probe] ||= begin
      dir = Dir.mktmpdir
      Minitest.after_run { FileUtils.rm_rf(dir) }
      build_and_unpack(dir, Parity.gem_probe(File.join(dir, "parity-bundle"), name: "ParityBundle"), name: "ParityBundle")
    end
  end

  def built(source)
    self.class.built[source] ||= begin
      dir = Dir.mktmpdir
      Minitest.after_run { FileUtils.rm_rf(dir) }
      build_and_unpack(dir, source)
    end
  end

  class << self
    def built = (@built ||= {})
  end

  def test_the_built_app_runs_with_no_ruby_environment
    Dir.mktmpdir do |dir|
      out, err, status = run_app({ "HOME" => dir }, app)

      assert_equal [expected, "", 0], [out, err, status.exitstatus]
    end
  end

  def test_the_built_app_ignores_a_hostile_ruby_environment
    Dir.mktmpdir do |dir|
      evil = File.join(dir, "evil")
      user_gems = File.join(dir, ".gem/ruby/4.0.0")
      FileUtils.mkdir_p([evil, File.join(user_gems, "gems/json-99.0.0/lib"), File.join(user_gems, "specifications")])
      leak = "raise 'the caller\\'s Ruby environment leaked into the app'\n"
      %w[json nonexistent bundler_setup].each { |name| File.write(File.join(evil, "#{name}.rb"), leak) }
      File.write(File.join(user_gems, "gems/json-99.0.0/lib/json.rb"), leak)
      File.write(File.join(user_gems, "specifications/json-99.0.0.gemspec"), <<~SPEC)
        Gem::Specification.new { |s| s.name = "json"; s.version = "99.0.0"; s.summary = "x"; s.authors = ["x"]; s.files = ["lib/json.rb"] }
      SPEC
      env = {
        "HOME" => dir,
        "RUBYLIB" => evil,
        "RUBYOPT" => "-rnonexistent",
        "GEM_HOME" => user_gems,
        "GEM_PATH" => user_gems,
        "BUNDLE_GEMFILE" => File.join(evil, "Gemfile"),
        "BUNDLER_SETUP" => File.join(evil, "bundler_setup.rb"),
        "RUBYGEMS_GEMDEPS" => "-",
        # RubyInstaller's: folders to load DLLs from, and putting them on
        # PATH. Windows' variable names ignore case, so a lowercase
        # bundle_ variable is Bundler's too.
        "RUBY_DLL_PATH" => evil,
        "RI_FORCE_PATH_FOR_DLL" => "1",
        "bundle_gemfile" => File.join(evil, "Gemfile"),
      }

      out, err, status = run_app(env, app)

      assert_equal [expected, "", 0], [out, err, status.exitstatus]
    end
  end

  # The launcher hides the person's Ruby settings from Ruby's boot, then
  # puts them back (ADR 003): the app's own gems stay the runtime's, and a
  # Ruby the app starts sees the person's settings, as under ruby main.rb.
  def test_the_persons_ruby_settings_reach_child_processes_but_not_the_apps_gems
    Dir.mktmpdir do |dir|
      gems = File.join(dir, "person-gems")
      env = { "HOME" => dir, "GEM_HOME" => gems, "bundle_gemfile" => File.join(dir, "Gemfile") }

      out, err, status = run_app(env, probe, "child-env", "GEM_HOME")
      assert_equal ["#{gems}\n", "", 0], [out, err, status.exitstatus]

      out, err, status = run_app(env, probe, "gem-path")
      assert_equal 0, status.exitstatus, err
      refute_includes out, gems
      assert_equal 1, out.lines.size, out
    end
  end

  # An app with a Gemfile gets the ENV bundle exec gives (ADR 005):
  # Bundler's settings over the person's, so a child Ruby runs in the
  # app's bundle with the person's RUBYOPT after Bundler's own, and
  # Bundler.with_original_env and with_unbundled_env, which a Bundler app
  # uses to start a person's own tools, give the person's environment
  # back. The app's own gems stay the runtime's. The child runs in a
  # UTF-8 locale: under a C locale, Bundler 4.0.20 itself fails to set up
  # a bundle whose path is not ASCII (SharedHelpers#clean_load_path), as
  # bundle exec would there.
  def test_a_bundler_apps_children_see_the_persons_ruby_settings_as_under_bundle_exec
    Dir.mktmpdir do |dir|
      gems = File.join(dir, "person-gems")
      locale = @platform.name.end_with?("darwin") ? "en_US.UTF-8" : "C.UTF-8"
      env = { "HOME" => dir, "LC_ALL" => locale, "GEM_HOME" => gems, "RUBYOPT" => "-W0", "BUNDLE_PERSON" => "1" }
      seen = -> (*argv) { run_app(env, bundled_probe, *argv).then { |out, err, status| [out.chomp, err, status.exitstatus] } }

      %w[original-child-env unbundled-child-env].each do |command|
        assert_equal [gems, "", 0], seen.call(command, "GEM_HOME"), command
        assert_equal ["-W0", "", 0], seen.call(command, "RUBYOPT"), command
      end
      assert_equal ["1", "", 0], seen.call("original-child-env", "BUNDLE_PERSON")
      assert_equal ["(unset)", "", 0], seen.call("unbundled-child-env", "BUNDLE_PERSON")
      assert_match %r{\A-r(?:\S*/)?bundler/setup -W0\z}, seen.call("child-env", "RUBYOPT").first
      refute_equal gems, seen.call("child-env", "GEM_HOME").first
      refute_includes seen.call("gem-path").first, gems
    end
  end

  def test_a_missing_main_rb_exits_with_ex_noinput
    main = File.join(File.realpath(File.dirname(app)), "app", "main.rb")
    File.rename(main, "#{main}.away")
    out, err, status = run_app({}, app)

    assert_equal ["", 66], [out, status.exitstatus]
    assert_equal "#{@platform.executable('Hello')}: this app is incomplete: #{main.tr('/', File::ALT_SEPARATOR || '/')} is missing\n",
      err.gsub("\r\n", "\n")
  ensure
    File.rename("#{main}.away", main) if main && File.exist?("#{main}.away")
  end

  # The gem-shaped app (ADR 005): exe/my_cool_app, with i18n and the
  # runtime's own build of sqlite3 set up by Bundler as bundle exec would.
  def test_the_gem_shaped_app_runs_with_its_gems_and_its_status
    Dir.mktmpdir do |dir|
      out, err, status = run_app({ "HOME" => dir }, my_cool_app, "5")

      assert_match my_cool_app_line, out
      assert_equal ["", 5], [err, status.exitstatus]
    end
  end

  # Nothing of the person's Bundler (their ~/.bundle/config, BUNDLE_*,
  # BUNDLER_VERSION) changes which gems the app loads, and running it
  # changes nothing in its folder: frozen, Bundler neither installs nor
  # rewrites the lockfile.
  def test_the_gem_shaped_app_ignores_the_persons_bundler_and_writes_nothing
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".bundle"))
      File.write(File.join(dir, ".bundle", "config"), <<~YAML)
        ---
        BUNDLE_GEMFILE: "#{File.join(dir, 'Gemfile')}"
        BUNDLE_FORCE_RUBY_PLATFORM: "true"
        BUNDLE_WITHOUT: "default"
        BUNDLE_PATH: "#{dir}"
        BUNDLE_AUTO_INSTALL: "true"
      YAML
      env = {
        "HOME" => dir,
        "USERPROFILE" => dir,
        "BUNDLE_GEMFILE" => File.join(dir, "Gemfile"),
        "BUNDLE_FROZEN" => "false",
        "BUNDLE_WITHOUT" => "default",
        "BUNDLE_APP_CONFIG" => dir,
        "BUNDLER_VERSION" => "2.1.0",
        "GEM_HOME" => dir,
        "RUBYOPT" => "-rnonexistent",
      }
      root = File.dirname(my_cool_app)
      before = snapshot(root)

      out, err, status = run_app(env, my_cool_app)

      assert_match my_cool_app_line, out
      assert_equal ["", 0], [err, status.exitstatus]
      assert_equal before, snapshot(root)
    end
  end

  def test_a_gem_shaped_app_without_its_program_exits_with_ex_noinput
    program = File.join(File.realpath(File.dirname(my_cool_app)), "app", "exe", "my_cool_app")
    File.rename(program, "#{program}.away")
    out, err, status = run_app({}, my_cool_app)

    assert_equal ["", 66], [out, status.exitstatus]
    assert_equal "#{@platform.executable('MyCoolApp')}: this app is incomplete: #{program.tr('/', File::ALT_SEPARATOR || '/')} is missing\n",
      err.gsub("\r\n", "\n")
  ensure
    File.rename("#{program}.away", program) if program && File.exist?("#{program}.away")
  end

  # Every file under +root+, with its size and modification time.
  def snapshot(root)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: root).sort.map do |path|
      stat = File.lstat(File.join(root, path))
      [path, stat.size, stat.mtime.to_f]
    end
  end

  def test_the_apps_exit_status_reaches_the_caller
    Dir.mktmpdir do |dir|
      out, _, status = run_app({ "HOME" => dir }, app, "3")

      assert_equal [expected, 3], [out, status.exitstatus]
    end
  end

  # examples/windowed_app, built as a windowed app (ADR 008): on macOS an
  # .app bundle that Apple's codesign verifies, strictly and deeply, and
  # whose Info.plist plutil reads; on Windows a GUI program; on Linux a
  # folder with a desktop entry. Run by its program, it writes its report
  # and exits with the status it is given; on Windows it has no console,
  # and its AppUserModelID is its identifier.
  def test_the_windowed_app_runs_from_its_bundle_or_folder
    Dir.mktmpdir do |dir|
      folder = File.dirname(build_and_unpack(dir, WINDOWED_APP, name: "Hello Window"))
      program = File.join(folder, @platform.executable("Hello Window"))
      case @platform.os
      when "darwin"
        bundle = File.join(folder, "Hello Window.app")
        program = File.join(bundle, "Contents", "MacOS", "Hello Window")
        out, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", bundle)
        assert_predicate status, :success?, out
        out, status = Open3.capture2e("plutil", "-extract", "CFBundleIdentifier", "raw", File.join(bundle, "Contents", "Info.plist"))
        assert_equal ["com.setdef.fledge.HelloWindow\n", true], [out, status.success?]
      when "windows"
        header = File.binread(program, 4096)
        assert_equal 2, header.byteslice(header.byteslice(0x3C, 4).unpack1("V") + 24 + 68, 2).unpack1("v"), "its PE Subsystem is GUI"
      else
        assert_includes File.read(File.join(folder, "com.setdef.fledge.HelloWindow.desktop")), "Exec=\"Hello Window\"\n"
      end

      report = File.join(dir, "report.json")
      _, err, status = run_app({ "HOME" => dir }, program, report, "4")

      assert_equal ["", 4], [err, status.exitstatus]
      facts = { "ruby" => "4.0.9", "platform" => expected_platform, "program" => "main.rb", "folder" => "app" }
      facts.merge!("console" => false, "app_user_model_id" => "com.setdef.fledge.HelloWindow") if @platform.windows?
      assert_equal facts, JSON.parse(File.read(report))
    end
  end

  # examples/windowed_app's installer (ADR 009), built beside its archive
  # from this computer's runtime: on macOS a disk image that hdiutil
  # verifies and attaches, whose bundle codesign verifies, strictly and
  # deeply, inside it, and runs from it; on Linux an AppImage that runs,
  # extracting itself where there is no FUSE, and that --appimage-extract
  # unpacks into an AppDir; on Windows a setup program, which Delivery
  # installs (.github/scripts/deliver-installer.ps1), compiled by the
  # Windows runtime's own NSIS. On Linux the build needs mksquashfs.
  def test_the_windowed_apps_installer_holds_the_app_and_runs_it
    Dir.mktmpdir do |dir|
      out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes, "XDG_CACHE_HOME" => File.join(dir, "cache") }, RbConfig.ruby,
        "-I", LIB, EXE, "build", "-o", File.join(dir, "dist"), WINDOWED_APP)
      assert_predicate status, :success?, err
      installer = File.expand_path(out.lines.fetch(1).chomp, Dir.pwd)
      report = File.join(dir, "report.json")
      facts = { "ruby" => "4.0.9", "platform" => expected_platform, "program" => "main.rb", "folder" => "app" }
      case @platform.os
      when "darwin"
        assert_equal "Hello Window-arm64-darwin.dmg", File.basename(installer)
        verified, status = Open3.capture2e("hdiutil", "verify", installer)
        assert_predicate status, :success?, verified
        DiskImages.mounted(installer) do |mount|
          bundle = File.join(mount, "Hello Window.app")
          signed, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", bundle)
          assert_predicate status, :success?, signed
          assert_equal "/Applications", File.readlink(File.join(mount, "Applications"))
          _, err, status = run_app({ "HOME" => dir }, File.join(bundle, "Contents", "MacOS", "Hello Window"), report, "3")
          assert_equal ["", 3], [err, status.exitstatus]
        end
      when "linux"
        assert_equal "Hello Window-#{@platform}.AppImage", File.basename(installer)
        _, err, status = run_app({ "HOME" => dir, "APPIMAGE_EXTRACT_AND_RUN" => "1", "TMPDIR" => dir }, installer, report, "3")
        assert_equal ["", 3], [err, status.exitstatus]
        extracted, status = Open3.capture2e(installer, "--appimage-extract", chdir: dir)
        assert_predicate status, :success?, extracted
        root = File.join(dir, "squashfs-root")
        assert_equal "Hello Window", File.readlink(File.join(root, "AppRun"))
        assert_path_exists File.join(root, "com.setdef.fledge.HelloWindow.desktop")
        assert_equal "com.setdef.fledge.HelloWindow.png", File.readlink(File.join(root, ".DirIcon"))
      else
        assert_equal "Hello Window-x64-mingw-ucrt-setup.exe", File.basename(installer)
        assert_equal "MZ", File.binread(installer, 2)
      end
      assert_equal facts, JSON.parse(File.read(report)).slice(*facts.keys) unless @platform.windows?
    end
  end

  # Builds the app in +source+ through the fledge executable, as a person
  # would, and unpacks its archive under a path with spaces and characters
  # outside ASCII. Returns the launcher's path. +name+ is the app's name,
  # when the caller knows it; reading it from the project would load a
  # copy of my_cool_app's gemspec, and so its version constant, again.
  def build_and_unpack(dir, source, name: Fledge::App.at(source).name)
    out, err, status = Open3.capture3({ "FLEDGE_RUNTIME_DIR" => @runtimes }, RbConfig.ruby, "-I", LIB, EXE, "build",
      "-o", File.join(dir, "dist"), source)
    assert_predicate status, :success?, err
    archive = File.expand_path(out.lines.first.to_s.chomp, Dir.pwd)

    place = File.join(dir, "My Apps", "Ünïcödé 日本")
    FileUtils.mkdir_p(place)
    unpack(archive, place)
    File.join(place, "#{name}-#{@platform}", @platform.executable(name))
  end

  # Windows' own Expand-Archive for a .zip, as a person on Windows has
  # it, and the system's tar for a .tar.gz.
  def unpack(archive, place)
    command = if @platform.windows?
      [
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "$ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $env:ARCHIVE -DestinationPath $env:PLACE",
]
    else
      ["tar", "-xzf", archive, "-C", place]
    end
    out, status = Open3.capture2e({ "ARCHIVE" => archive, "PLACE" => place }, *command)
    assert_predicate status, :success?, out
  end

  # Runs the app, never through a shell, with nothing in its environment
  # but +env+. Windows' network and cryptography libraries need
  # SystemRoot, so on Windows that stays, with a PATH of System32.
  def run_app(env, app, *argv)
    if @platform.windows?
      system_root = ENV.fetch("SystemRoot", "C:\\Windows")
      env = { "SystemRoot" => system_root, "PATH" => File.join(system_root, "System32") }.merge(env)
    end
    Open3.capture3(env, [app, app], *argv, unsetenv_others: true, chdir: Dir.tmpdir)
  end
end
