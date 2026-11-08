# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/disk_images"
require_relative "support/gems"
require "json"
require "open3"

# Fledge::Assembly with fake runtimes, on the computer the tests run on:
# each platform's app is built on that platform (ADR 010), so a test of
# what only one platform's tools make runs only there, and CI runs the
# tests on every platform.
class AssemblyTest < Minitest::Test
  LINUX = Fledge::Platform.find("x86_64-linux")
  MACOS = Fledge::Platform.find("arm64-darwin")
  WINDOWS = Fledge::Platform.find("x64-mingw-ucrt")

  # A windowed app with an icon, whose name has a space, and, unless
  # +installers+ says otherwise, no installers.
  module WindowedApp
    def self.write(dir, installers: "[]")
      root = FakeApp.write(dir, "window")
      File.write(File.join(root, "fledge.yml"),
        "name: Hello Window\nkind: windowed\nidentifier: com.example.HelloWindow\nicon: art\n#{"installers: #{installers}\n" if installers}")
      FakeRuntime.icons(root, "art")
      root
    end
  end

  RUNTIME_FILES = %w[
    lib
    lib/current
    lib/ruby
    lib/ruby/4.0.0
    lib/ruby/4.0.0/fake-arch
    lib/ruby/4.0.0/fake-arch/rbconfig.rb
    lib/ruby/gems
    lib/ruby/gems/4.0.0
    lib/ruby/gems/4.0.0/plugins
    lib/ruby/gems/4.0.0/plugins/rdoc_plugin.rb
    lib/ruby/gems/4.0.0/specifications
    lib/ruby/gems/4.0.0/specifications/csv-3.3.5.gemspec
    lib/ruby/gems/4.0.0/specifications/default
    lib/ruby/gems/4.0.0/specifications/default/json-2.18.0.gemspec
    lib/ruby/gems/4.0.0/specifications/rdoc-7.0.4.gemspec
    lib/ruby/stdlib.rb
  ].freeze

  # What a runtime keeps for installers, in its installer folder.
  APPIMAGE_RUNTIME = Fledge::Entry.file("tools/appimage-runtime", "\x7FELF runtime".b, mode: 0o755)

  def assemble(dir, app_root, platform: LINUX, runtime: FakeRuntime.write(dir, platform), app_files: {}, files: [])
    out = File.join(dir, "dist")
    Fledge::Assembly.new(app: Fledge::App.at(app_root), platform:, runtime:, out:, app_files:, files:).call
  end

  # What a build left in +dir+'s dist folder, but the cache directory
  # tag the folder keeps.
  def left_in(dir)
    Dir.children(File.join(dir, "dist")) - [Fledge::CacheTag::FILE]
  end

  # The archive at +archive+, unpacked by the system's tar into a folder
  # of +dir+, whose path it returns.
  def unpacked(dir, archive)
    place = File.join(dir, "unpacked")
    FileUtils.rm_rf(place)
    FileUtils.mkdir_p(place)
    out, status = Open3.capture2e(Fledge::Archive.tar, "-xf", archive, "-C", place)
    assert_predicate status, :success?, out
    place
  end

  # Every path below +folder+, relative to it.
  def tree(folder)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: folder).reject { |path| File.basename(path) == "." }.sort
  end

  def unix!
    skip "a Unix app's symbolic links and modes are built on macOS or Linux" if Gem.win_platform?
  end

  # A Windows app is built on Windows, with the real Windows runtime's
  # launchers and rcedit (FakeRuntime.windows).
  def windows!
    skip "a Windows app is built on Windows" unless Gem.win_platform?
    return if FakeRuntime.windows

    message = "no Windows runtime in FLEDGE_RUNTIME_DIR or tmp/runtime, whose launchers and rcedit these tests run"
    ENV["FLEDGE_REQUIRE_RUNTIME"] ? flunk(message) : skip(message)
  end

  # The PE Subsystem of the Windows program at +path+: 2 for a GUI
  # program, 3 for a console one, as the runtime's llvm-readobj reads it.
  def subsystem(path)
    TestReaders.need(self, :pe)
    Fledge::Binary.read([path], readers: TestReaders.all).fetch(path).subsystem
  end

  # The version information Windows reads from the program at +path+, as
  # Explorer's Properties dialog shows it.
  def version_info(path)
    script = "(Get-Item -LiteralPath $env:PROGRAM).VersionInfo | Select-Object FileDescription, ProductName, CompanyName, " \
      "LegalCopyright, OriginalFilename, FileVersion, ProductVersion, FileMajorPart | ConvertTo-Json"
    out, status = Open3.capture2e({ "PROGRAM" => path }, "powershell", "-NoProfile", "-NonInteractive", "-Command", script)
    assert_predicate status, :success?, out
    JSON.parse(out)
  end

  def mac!
    skip "a Mac app is built on a Mac" unless RUBY_PLATFORM.include?("darwin")
  end

  # An AppImage is built on Linux, with mksquashfs (as app_image_test.rb
  # checks).
  def appimage!
    skip "an AppImage is built on Linux, with mksquashfs" unless RUBY_PLATFORM.include?("linux") && system("mksquashfs", "-version", out: File::NULL)
  end

  def test_the_runtime_and_app_land_in_a_folder_and_an_archive_with_the_launcher_renamed
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, "helper.rb"), "")

      archive = assemble(dir, app)

      assert_equal File.join(dir, "dist", "Hello-x86_64-linux.tar.gz"), archive
      folder = File.join(dir, "dist", "Hello-x86_64-linux")
      assert_equal %w[Hello app fledge.cfg lib], Dir.children(folder).sort
      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Hello"))
      assert_equal "puts 'hi'\n", File.read(File.join(folder, "app/main.rb"))
      assert_equal "ruby", File.readlink(File.join(folder, "lib/current"))
      assert_equal ["Hello-x86_64-linux"], left_in(dir) - [File.basename(archive)], "no work folder is left"
      assert Fledge::CacheTag.tagged?(File.join(dir, "dist")), "the folder the build made is tagged"

      place = unpacked(dir, archive)
      top = File.join(place, "Hello-x86_64-linux")
      assert_equal ["Hello", "app", "app/helper.rb", "app/main.rb", "fledge.cfg", *RUNTIME_FILES].sort, tree(top)
      assert_equal 0o755, File.stat(File.join(top, "Hello")).mode & 0o777
      assert File.symlink?(File.join(top, "lib/current"))
    end
  end

  # The launcher reads fledge.cfg, beside it, to learn what to run
  # (runtime/launcher/config.c).
  def test_fledge_cfg_names_the_entry_point_and_a_gemfile
    unix!
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      hello = FakeApp.write(dir)
      assemble(dir, hello)
      assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\nentry = main.rb\n",
        File.read(File.join(dir, "dist/Hello-x86_64-linux/fledge.cfg"))

      project = FakeProject.write(dir, name: "my_cool_app")
      assemble(dir, File.join(project, "exe/my_cool_app"))
      assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\n" \
        "entry = exe/my_cool_app\ngemfile = Gemfile\n", File.read(File.join(dir, "dist/MyCoolApp-x86_64-linux/fledge.cfg"))
    end
  end

  def test_app_files_replace_or_join_the_projects_and_files_join_the_runtimes
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, "hello.gemspec.txt"), "original\n")
      gem = Fledge::Entry.file("lib/ruby/gems/4.0.0/gems/foo-1.0.0/lib/foo.rb", "# foo\n")
      info = Fledge::Entry.file("lib/ruby/gems/4.0.0/build_info/foo-1.0.0.info", "--with-foo\n")

      archive = assemble(dir, app, app_files: { "hello.gemspec.txt" => "evaluated\n", ".bundle/config" => "---\n" },
        files: [gem, Fledge::Entry.directory("lib/ruby/gems/4.0.0"), info])

      folder = File.join(dir, "dist", "Hello-x86_64-linux")
      assert_equal "evaluated\n", File.read(File.join(folder, "app/hello.gemspec.txt"))
      assert_equal "---\n", File.read(File.join(folder, "app/.bundle/config"))
      assert_equal "# foo\n", File.read(File.join(folder, gem.path))
      top = File.join(unpacked(dir, archive), "Hello-x86_64-linux")
      assert_equal "# foo\n", File.read(File.join(top, gem.path))
      assert_equal "--with-foo\n", File.read(File.join(top, info.path))
    end
  end

  def test_an_added_file_may_not_replace_the_runtimes_and_nothing_is_left
    unix!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, LINUX)
      clash = Fledge::Entry.file("lib/ruby/gems/4.0.0/specifications/csv-3.3.5.gemspec", "# mine\n")

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:, files: [clash]) }

      assert_equal "#{clash.path} is in #{runtime} already, so the build can't add its own", error.message
      assert_empty left_in(dir)
    end
  end

  # Windows' layout differs from Unix's (Ruby's own tree in ruby\, not
  # lib/ beside the launcher), but assembly hardly cares: it renames
  # launcher.exe, with the app's version information in it, and copies the
  # rest as the runtime holds it, but for launcherw.exe, which a console
  # app does not run. Windows' own tar writes the .zip.
  def test_a_windows_app_lands_in_a_folder_and_a_zip_with_the_exe_renamed
    windows!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, WINDOWS, extra: [Fledge::Entry.file("ruby/bin/x64-ucrt-ruby400.dll", "MZ", mode: 0o755)])

      app = FakeApp.write(dir)
      archive = assemble(dir, app, platform: WINDOWS, runtime:)

      assert_equal File.join(dir, "dist", "Hello-x64-mingw-ucrt.zip"), archive
      folder = File.join(dir, "dist", "Hello-x64-mingw-ucrt")
      assert_equal %w[Hello.exe app fledge.cfg notices ruby], Dir.children(folder).sort
      program = File.join(folder, "Hello.exe")
      assert_equal 3, subsystem(program)
      info = version_info(program)
      assert_equal ["Hello", "Hello", "Hello.exe", "0.0.0", "0.0.0"],
        info.values_at("FileDescription", "ProductName", "OriginalFilename", "FileVersion", "ProductVersion")
      top = File.join(unpacked(dir, archive), "Hello-x64-mingw-ucrt")
      assert_path_exists File.join(top, "ruby/bin/x64-ucrt-ruby400.dll")
      assert_equal File.binread(File.join(folder, "Hello.exe")), File.binread(File.join(top, "Hello.exe"))
      assert_equal File.binread(File.join(app, "main.rb")), File.binread(File.join(top, "app/main.rb"))
    end
  end

  # A windowed app runs launcherw.exe, a GUI program, renamed, with its
  # identity; fledge.cfg names its identifier for the launcher's
  # AppUserModelID.
  def test_a_windowed_windows_app_runs_the_gui_launcher
    windows!
    Dir.mktmpdir do |dir|
      app = WindowedApp.write(dir)
      assemble(dir, app, platform: WINDOWS)

      folder = File.join(dir, "dist", "Hello Window-x64-mingw-ucrt")
      assert_equal ["Hello Window.exe", "app", "fledge.cfg", "notices", "ruby"], Dir.children(folder).sort
      program = File.join(folder, "Hello Window.exe")
      assert_equal 2, subsystem(program)
      assert_equal "Hello Window", version_info(program).fetch("FileDescription")
      assert_includes File.read(File.join(folder, "fledge.cfg")), "\nidentifier = com.example.HelloWindow\n"
    end
  end

  def test_a_windowed_app_needs_a_runtime_with_a_windowed_launcher
    windows!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.pack(File.join(dir, "old.tar.gz"), "top", [Fledge::Entry.file("launcher.exe", FakeRuntime::WINDOWS_CONSOLE, mode: 0o755)])

      error = assert_raises(Fledge::Error) { assemble(dir, WindowedApp.write(dir), platform: WINDOWS, runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcherw.exe", error.message
    end
  end

  # A windowed app on macOS is an .app bundle: the launcher in MacOS, the
  # runtime and the app in Resources, linked from MacOS where the launcher
  # and Ruby look for them, an Info.plist and icon, and codesign's seal
  # and ad hoc signature over all of it.
  def test_a_windowed_macos_app_is_a_signed_bundle
    mac!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, MACOS, launcher: File.binread("/usr/bin/true"), extra: [Fledge::Entry.file("libexec/cert.pem", "pem")])
      archive = assemble(dir, WindowedApp.write(dir), platform: MACOS, runtime:)

      folder = File.join(dir, "dist", "Hello Window-arm64-darwin")
      contents = File.join(folder, "Hello Window.app", "Contents")
      assert_equal ["Hello Window.app"], Dir.children(folder)
      assert_equal %w[Info.plist MacOS Resources _CodeSignature], Dir.children(contents).sort
      assert_equal ["Hello Window", "app", "fledge.cfg", "lib", "libexec"], Dir.children(File.join(contents, "MacOS")).sort
      %w[app fledge.cfg lib libexec].each do |name|
        assert_equal "../Resources/#{name}", File.readlink(File.join(contents, "MacOS", name)), name
      end
      assert_equal ["Hello Window.icns", "app", "fledge.cfg", "lib", "libexec"], Dir.children(File.join(contents, "Resources")).sort
      plist = File.read(File.join(contents, "Info.plist"))
      assert_includes plist, "<key>CFBundleIdentifier</key>\n\t<string>com.example.HelloWindow</string>"
      assert_includes plist, "<key>CFBundleExecutable</key>\n\t<string>Hello Window</string>"
      assert_includes plist, "<key>NSHighResolutionCapable</key>\n\t<true/>"

      bundle = File.join(unpacked(dir, archive), "Hello Window-arm64-darwin", "Hello Window.app")
      verified, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", bundle)
      assert_predicate status, :success?, verified
      signed, = Open3.capture2e("codesign", "--display", "--verbose=2", bundle)
      assert_includes signed, "Identifier=com.example.HelloWindow"
      assert_includes signed, "Signature=adhoc"
      assert_equal 0o755, File.stat(File.join(bundle, "Contents/MacOS/Hello Window")).mode & 0o777
      assert File.symlink?(File.join(bundle, "Contents/MacOS/lib"))
    end
  end

  # fledge.yml's macos: build is the bundle's CFBundleVersion, as plutil
  # reads it, and the version's numbers stay CFBundleShortVersionString;
  # without it, both are the version's.
  def test_a_macos_build_number_is_the_bundles_cfbundleversion
    mac!
    Dir.mktmpdir do |dir|
      root = WindowedApp.write(dir)
      File.write(File.join(root, "fledge.yml"), "version: \"2.1.0.pre.3\"\n#{File.read(File.join(root, 'fledge.yml'))}")
      read = lambda do |key|
        runtime = FakeRuntime.write(dir, MACOS, launcher: File.binread("/usr/bin/true"))
        assemble(dir, root, platform: MACOS, runtime:)
        plist = File.join(dir, "dist", "Hello Window-arm64-darwin", "Hello Window.app", "Contents", "Info.plist")
        out, status = Open3.capture2e("plutil", "-extract", key, "raw", plist)
        assert_predicate status, :success?, out
        out.strip
      end
      assert_equal %w[2.1.0 2.1.0], [read.call("CFBundleVersion"), read.call("CFBundleShortVersionString")]

      File.write(File.join(root, "fledge.yml"), "#{File.read(File.join(root, 'fledge.yml'))}macos:\n  build: \"2.1.417\"\n")
      assert_equal %w[2.1.417 2.1.0], [read.call("CFBundleVersion"), read.call("CFBundleShortVersionString")]
    end
  end

  # A project of several programs (ADR 024): a windowed one, with an
  # icon, and two console ones, sharing one project.
  module Programs
    def self.write(dir, installers: "[]")
      root = FakeApp.write(dir, "game")
      FileUtils.mkdir_p(File.join(root, "bin"))
      %w[gui.rb bin/cli bin/tui].each { |path| File.write(File.join(root, path), "") }
      File.write(File.join(root, "fledge.yml"), <<~YAML)
        name: Game
        version: "1.2.3"
        installers: #{installers}
        programs:
          - path: gui.rb
            name: Play Game
            kind: windowed
            identifier: com.example.Game
            icon: art
          - path: bin/cli
            name: game-cli
          - path: bin/tui
            identifier: com.example.GameTui
      YAML
      FakeRuntime.icons(root, "art")
      root
    end
  end

  # Each program is a copy of the launcher in the one folder, beside one
  # runtime and one app folder, and fledge.cfg gives each its section.
  def test_several_programs_share_one_folder_runtime_and_project
    unix!
    Dir.mktmpdir do |dir|
      archive = assemble(dir, Programs.write(dir))

      folder = File.join(dir, "dist", "Game-x86_64-linux")
      assert_equal File.join(dir, "dist", "Game-x86_64-linux.tar.gz"), archive
      assert_equal ["Play Game", "app", "com.example.Game.desktop", "fledge.cfg", "game-cli", "lib", "share", "tui"], Dir.children(folder).sort
      ["Play Game", "game-cli", "tui"].each do |program|
        assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, program)), program
        assert_equal 0o755, File.stat(File.join(folder, program)).mode & 0o777, program
      end
      assert_includes File.read(File.join(folder, "com.example.Game.desktop")), "Exec=\"Play Game\"\n"
      assert_equal <<~CFG, File.read(File.join(folder, "fledge.cfg"))
        # Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's programs run (ADR 024).
        [Play Game]
        entry = gui.rb
        identifier = com.example.Game

        [game-cli]
        entry = bin/cli

        [tui]
        entry = bin/tui
        identifier = com.example.GameTui
      CFG
      assert_equal ["Play Game", "app", "com.example.Game.desktop", "fledge.cfg", "game-cli", "lib", "share", "tui"],
        Dir.children(File.join(unpacked(dir, archive), "Game-x86_64-linux")).sort
    end
  end

  # The Gemfile all the programs share stays above their sections.
  def test_several_programs_share_one_gemfile
    Dir.mktmpdir do |dir|
      root = Programs.write(dir)
      File.write(File.join(root, "Gemfile"), "")

      text = Fledge::Assembly.launch_config(Fledge::App.at(root))
      assert text.start_with?("# Written by fledge build: what this app's programs run (ADR 024).\ngemfile = Gemfile\n\n[Play Game]\n"), text
      assert_equal 1, text.scan("gemfile").size
    end
  end

  # The libraries fledge.yml lists as the Linux distribution's (ADR 030)
  # reach a Linux launcher, which says which one a computer lacks before
  # Ruby starts, once for all the programs; other systems' launchers are
  # not told.
  def test_a_linux_launcher_is_told_the_system_libraries_the_gems_load
    unix!
    Dir.mktmpdir do |dir|
      hello = FakeApp.write(dir)
      File.write(File.join(hello, "fledge.yml"), "linux:\n  system_libraries: [libgtk-3.so.0, libwebkit2gtk-4.1.so.0]\n")
      assemble(dir, hello)
      assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\nentry = main.rb\n" \
        "system_libraries = libgtk-3.so.0 libwebkit2gtk-4.1.so.0\n", File.read(File.join(dir, "dist/Hello-x86_64-linux/fledge.cfg"))
      assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = main.rb\n",
        Fledge::Assembly.launch_config(Fledge::App.at(hello))

      root = Programs.write(dir)
      File.write(File.join(root, "Gemfile"), "")
      File.write(File.join(root, "fledge.yml"), "#{File.read(File.join(root, 'fledge.yml'))}linux:\n  system_libraries: [libgtk-3.so.0]\n")
      text = Fledge::Assembly.launch_config(Fledge::App.at(root), system_libraries: ["libgtk-3.so.0"])
      assert text.start_with?("# Written by fledge build: what this app's programs run (ADR 024).\ngemfile = Gemfile\n" \
        "system_libraries = libgtk-3.so.0\n\n[Play Game]\n"), text
    end
  end

  # One of the programs, built on its own, is an app of one program, as
  # a project with no programs builds.
  def test_one_of_several_programs_builds_alone
    unix!
    Dir.mktmpdir do |dir|
      assemble(dir, File.join(Programs.write(dir), "bin/cli"))

      folder = File.join(dir, "dist", "game-cli-x86_64-linux")
      assert_equal %w[app fledge.cfg game-cli lib], Dir.children(folder).sort
      assert_equal "# Written by fledge build #{Fledge::VERSION} for x86_64-linux: what this app's program runs (ADR 005).\nentry = bin/cli\n",
        File.read(File.join(folder, "fledge.cfg"))
    end
  end

  # No program may take a name the runtime holds.
  def test_a_program_named_as_the_runtimes_files_is_refused
    unix!
    Dir.mktmpdir do |dir|
      root = Programs.write(dir)
      File.write(File.join(root, "fledge.yml"), File.read(File.join(root, "fledge.yml")).sub("name: game-cli", "name: Lib"))

      error = assert_raises(Fledge::Error) { assemble(dir, root) }
      assert_equal "an app named Lib would collide with the runtime's lib. Give it another name.", error.message
      assert_empty left_in(dir)
    end
  end

  # On macOS the windowed program's bundle holds everything: the console
  # programs are copies of the launcher in its MacOS folder, sealed by
  # its signature, and linked from the app's folder.
  def test_on_macos_console_programs_live_in_the_windowed_programs_bundle
    mac!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, MACOS, launcher: File.binread("/usr/bin/true"), extra: [Fledge::Entry.file("libexec/cert.pem", "pem")])
      archive = assemble(dir, Programs.write(dir), platform: MACOS, runtime:)

      folder = File.join(dir, "dist", "Game-arm64-darwin")
      assert_equal ["Play Game.app", "game-cli", "tui"], Dir.children(folder).sort
      macos = File.join(folder, "Play Game.app", "Contents", "MacOS")
      assert_equal ["Play Game", "app", "fledge.cfg", "game-cli", "lib", "libexec", "tui"], Dir.children(macos).sort
      %w[game-cli tui].each do |program|
        assert_equal "Play Game.app/Contents/MacOS/#{program}", File.readlink(File.join(folder, program)), program
        assert_equal File.binread("/usr/bin/true"), File.binread(File.join(macos, program)), program
      end
      assert_includes File.read(File.join(macos, "fledge.cfg")), "\n[game-cli]\nentry = bin/cli\n"

      place = File.join(unpacked(dir, archive), "Game-arm64-darwin")
      assert_equal "Play Game.app/Contents/MacOS/tui", File.readlink(File.join(place, "tui"))
      verified, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", "--verbose=2", File.join(place, "Play Game.app"))
      assert_predicate status, :success?, verified
      assert_includes verified, "MacOS/game-cli", "the bundle's signature covers its console programs"
    end
  end

  # On Windows each program is its own launcher: the GUI one for the
  # windowed program, the console one for the rest, each with its own
  # name in its version information.
  def test_on_windows_each_program_is_its_kinds_launcher
    windows!
    Dir.mktmpdir do |dir|
      assemble(dir, Programs.write(dir), platform: WINDOWS)

      folder = File.join(dir, "dist", "Game-x64-mingw-ucrt")
      assert_equal ["Play Game.exe", "app", "fledge.cfg", "game-cli.exe", "notices", "ruby", "tui.exe"], Dir.children(folder).sort
      assert_equal [2, 3, 3], ["Play Game.exe", "game-cli.exe", "tui.exe"].map { |program| subsystem(File.join(folder, program)) }
      assert_equal ["Play Game", "game-cli", "tui"],
        ["Play Game.exe", "game-cli.exe", "tui.exe"].map { |program| version_info(File.join(folder, program)).fetch("FileDescription") }
    end
  end

  # A windowed app on Linux keeps the folder, with a desktop entry beside
  # the program and its icons in the hicolor theme's folders.
  def test_a_windowed_linux_app_has_a_desktop_entry_and_icons
    unix!
    Dir.mktmpdir do |dir|
      assemble(dir, WindowedApp.write(dir))

      folder = File.join(dir, "dist", "Hello Window-x86_64-linux")
      assert_equal ["Hello Window", "app", "com.example.HelloWindow.desktop", "fledge.cfg", "lib", "share"], Dir.children(folder).sort
      assert_includes File.read(File.join(folder, "com.example.HelloWindow.desktop")), "Exec=\"Hello Window\"\n"
      assert_path_exists File.join(folder, "share/icons/hicolor/512x512/apps/com.example.HelloWindow.png")
      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Hello Window"))
    end
  end

  # A windowed Linux app takes the icon sizes its project has, at least
  # one, and the build names the rest on its log; with all six it says
  # nothing, and with none it fails as a missing icon does.
  def test_a_windowed_linux_app_takes_the_icon_sizes_there_are
    unix!
    Dir.mktmpdir do |dir|
      root = WindowedApp.write(dir)
      log = StringIO.new
      Fledge::Assembly.new(app: Fledge::App.at(root), platform: LINUX, runtime: FakeRuntime.write(dir, LINUX), out: File.join(dir, "dist"), log:).call
      assert_equal "", log.string

      [16, 64, 512].each { |size| File.delete(File.join(root, "art-#{size}.png")) }
      Fledge::Assembly.new(app: Fledge::App.at(root), platform: LINUX, runtime: FakeRuntime.write(dir, LINUX), out: File.join(dir, "dist"), log:).call
      assert_equal "fledge build: warning: the icon has no art-16.png, art-64.png, art-512.png, so Linux desktops scale the nearest size there is\n",
        log.string
      icons = File.join(dir, "dist", "Hello Window-x86_64-linux", "share/icons/hicolor")
      assert_equal %w[128x128 256x256 32x32], Dir.children(icons).sort

      Dir.glob(File.join(root, "art-*.png")).each { |png| File.delete(png) }
      error = assert_raises(Fledge::Error) { assemble(dir, root) }
      assert_includes error.message, "the icon art-16.png does not exist."
    end
  end

  # A windowed app gets its platform's installer by default (ADR 009),
  # written beside its archive from its folder and the runtime's tools
  # folder, which neither the folder nor the archive holds.
  def test_a_windowed_linux_app_gets_an_appimage_from_the_runtimes_tools_folder
    appimage!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, LINUX, extra: [APPIMAGE_RUNTIME])
      app = Fledge::App.at(WindowedApp.write(dir, installers: nil))
      assembly = Fledge::Assembly.new(app:, platform: LINUX, runtime:, out: File.join(dir, "dist"))
      archive = assembly.call

      image = File.join(dir, "dist", "Hello Window-x86_64-linux.AppImage")
      assert_equal [image], assembly.installers
      assert_equal APPIMAGE_RUNTIME.content, File.binread(image, APPIMAGE_RUNTIME.content.bytesize)
      refute_path_exists File.join(dir, "dist", "Hello Window-x86_64-linux", "tools")
      assert(tree(unpacked(dir, archive)).none? { |path| path.include?("tools") })
    end
  end

  # hdiutil writes the disk image of the signed bundle, with the link to
  # Applications beside it, and the bundle stays signed in it.
  def test_a_windowed_macos_app_gets_a_disk_image_of_its_bundle
    mac!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, MACOS, launcher: File.binread("/usr/bin/true"))
      app = Fledge::App.at(WindowedApp.write(dir, installers: nil))
      assembly = Fledge::Assembly.new(app:, platform: MACOS, runtime:, out: File.join(dir, "dist"))
      assembly.call

      image = File.join(dir, "dist", "Hello Window-arm64-darwin.dmg")
      assert_equal [image], assembly.installers
      DiskImages.mounted(image) do |mount|
        assert_equal ["Applications", "Hello Window.app"], Dir.children(mount).reject { |name| name.start_with?(".") }.sort
        assert_equal "/Applications", File.readlink(File.join(mount, "Applications"))
        verified, status = Open3.capture2e("codesign", "--verify", "--strict", "--deep", File.join(mount, "Hello Window.app"))
        assert_predicate status, :success?, verified
      end
    end
  end

  # The fake Windows runtime has the real runtime's launchers and rcedit
  # but no NSIS, so its installer fails, and leaves nothing behind.
  def test_a_windows_runtime_without_nsis_fails_and_leaves_nothing
    windows!
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { assemble(dir, WindowedApp.write(dir, installers: "[nsis]"), platform: WINDOWS) }

      assert_includes error.message, "the runtime has no tools/nsis"
      assert_empty left_in(dir)
    end
  end

  def test_a_build_without_the_runtimes_tools_fails_and_leaves_nothing
    unix!
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { assemble(dir, WindowedApp.write(dir, installers: nil)) }

      assert_includes error.message, "the runtime has no tools/appimage-runtime"
      assert_empty left_in(dir)
    end
  end

  # A console app on macOS stays a folder with the launcher as it came.
  def test_a_console_macos_app_is_a_folder
    unix!
    Dir.mktmpdir do |dir|
      assemble(dir, FakeApp.write(dir), platform: MACOS)

      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(dir, "dist", "Hello-arm64-darwin", "Hello"))
    end
  end

  def test_a_windows_runtime_without_launcher_exe_is_refused
    windows!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.pack(File.join(dir, "unix-launcher.tar.gz"), "top", [Fledge::Entry.file("launcher", "", mode: 0o755)])

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), platform: WINDOWS, runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcher.exe", error.message
      assert_empty left_in(dir)
    end
  end

  # A .zip for Windows holds no symbolic links, and Windows makes them
  # only with privileges, so an app with one is refused.
  def test_a_symlink_in_an_app_for_windows_is_refused_and_nothing_is_left
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.symlink("main.rb", File.join(app, "link.rb"))

      error = assert_raises(Fledge::Error) { assemble(dir, app, platform: WINDOWS) }

      assert_equal "Hello-x64-mingw-ucrt/app/link.rb is a symbolic link, which a .zip for Windows cannot hold. " \
        "Replace it with what it points to.", error.message
      assert_empty left_in(dir)
    end
  end

  def test_a_build_replaces_the_previous_one
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      assemble(dir, app)
      stale = File.join(dir, "dist/Hello-x86_64-linux/stale.txt")
      File.write(stale, "old")

      assemble(dir, app)

      refute_path_exists stale
    end
  end

  def test_build_output_inside_the_app_is_not_copied_into_the_app
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      runtime = FakeRuntime.write(dir, LINUX)
      out = File.join(app, "dist")
      2.times { Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out:).call }

      assert_equal ["main.rb"], Dir.children(File.join(out, "Hello-x86_64-linux/app"))
    end
  end

  # The names of what +archive+ holds, as the system's tar lists them.
  def archived(archive)
    out, status = Open3.capture2e(Fledge::Archive.tar, "-tzf", archive)
    assert_predicate status, :success?, out
    out.lines.map { |line| line.chomp.delete_suffix("/") }
  end

  # ADR 005, section 1: a build into dist, and then one into out, a
  # folder of its own, ships the project, not the first build.
  def test_a_build_into_another_folder_leaves_out_the_earlier_builds
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      runtime = FakeRuntime.write(dir, LINUX)
      first = Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out: File.join(app, "dist")).call

      second = Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out: File.join(app, "out")).call

      assert_equal ["main.rb"], Dir.children(File.join(app, "out/Hello-x86_64-linux/app"))
      assert_equal %w[Hello-x86_64-linux/app Hello-x86_64-linux/app/main.rb], archived(second).grep(%r{\AHello-x86_64-linux/app(/|\z)})
      assert_equal archived(first).sort, archived(second).sort
      assert_in_delta File.size(first), File.size(second), File.size(first) * 0.05
    end
  end

  def test_builds_into_two_new_folders_ship_neither_in_the_other
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      runtime = FakeRuntime.write(dir, LINUX)
      %w[dist-deb dist-appimage dist-deb].each do |out|
        Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out: File.join(app, out)).call
      end

      %w[dist-deb dist-appimage].each do |out|
        assert_equal ["main.rb"], Dir.children(File.join(app, out, "Hello-x86_64-linux/app")), out
        assert_equal %w[CACHEDIR.TAG Hello-x86_64-linux Hello-x86_64-linux.tar.gz], Dir.children(File.join(app, out)).sort, out
      end
    end
  end

  # A dist folder of the project's own, which no build went to, ships as
  # any other folder does when the build goes elsewhere.
  def test_a_folder_named_dist_that_holds_no_build_ships
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      FileUtils.mkdir_p(File.join(app, "dist"))
      File.write(File.join(app, "dist/index.html"), "the app's own")
      runtime = FakeRuntime.write(dir, LINUX)

      Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out: File.join(dir, "builds")).call

      assert_equal "the app's own", File.read(File.join(dir, "builds/Hello-x86_64-linux/app/dist/index.html"))
      refute_path_exists File.join(app, "dist/CACHEDIR.TAG")
    end
  end

  def test_an_app_named_like_a_runtime_folder_is_refused_and_nothing_is_left
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir, "lib")
      File.write(File.join(app, "fledge.yml"), "name: LIB\n")

      error = assert_raises(Fledge::Error) { assemble(dir, app) }

      assert_equal "an app named LIB would collide with the runtime's lib. Give it another name.", error.message
      assert_empty left_in(dir)
    end
  end

  def test_an_app_named_app_or_fledge_cfg_is_refused
    Dir.mktmpdir do |dir|
      { "App" => "its own app folder", "fledge.cfg" => "the file that says what it runs" }.each do |name, what|
        app = FakeApp.write(dir, "x#{name.size}")
        File.write(File.join(app, "fledge.yml"), "name: #{name}\n")

        error = assert_raises(Fledge::Error, name) { assemble(dir, app, runtime: "unused.tar.gz") }
        assert_equal "an app named #{name} would collide with #{what}. Give it another name.", error.message
      end
    end
  end

  def test_an_entry_point_fledge_cfg_cannot_hold_is_refused
    unix!
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, " spaced.rb"), "")

      error = assert_raises(Fledge::Error) { assemble(dir, File.join(app, " spaced.rb")) }
      assert_equal "\" spaced.rb\" can't be an app's program or Gemfile: its name begins or ends with a space, or holds a line break",
        error.message
    end
  end

  def test_a_runtime_without_a_launcher_is_refused
    unix!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.pack(File.join(dir, "empty.tar.gz"), "top", [Fledge::Entry.file("README", "")])

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcher", error.message
    end
  end

  def test_a_runtime_with_two_top_folders_is_refused
    unix!
    Dir.mktmpdir do |dir|
      stage = File.join(dir, "stage")
      Fledge::Entry.file("a/launcher", "", mode: 0o755).write_into(stage)
      Fledge::Entry.file("b/x", "").write_into(stage)
      runtime = File.join(dir, "two.tar.gz")
      out, status = Open3.capture2e("tar", "-czf", runtime, "-C", stage, "a", "b")
      assert_predicate status, :success?, out

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it holds both a/ and b", error.message
    end
  end

  def test_a_runtime_holding_an_app_or_a_fledge_cfg_is_refused
    unix!
    Dir.mktmpdir do |dir|
      { "app/main.rb" => "an app folder", "fledge.cfg" => "a fledge.cfg" }.each do |path, what|
        runtime = FakeRuntime.write(dir, LINUX, extra: [Fledge::Entry.file(path, "")])

        error = assert_raises(Fledge::Error, path) { assemble(dir, FakeApp.write(dir), runtime:) }
        assert_equal "#{runtime} is not a Fledge runtime: it holds #{what}", error.message
      end
    end
  end

  def test_the_base_name_is_name_dash_platform
    Dir.mktmpdir do |dir|
      assembly = Fledge::Assembly.new(app: Fledge::App.at(FakeApp.write(dir)), platform: LINUX, runtime: "r", out: "/o")

      assert_equal "Hello-x86_64-linux", assembly.base_name
    end
  end
end
