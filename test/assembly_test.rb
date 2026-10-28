# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/disk_images"
require_relative "support/gems"
require_relative "support/zip_reader"

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
        "name: Hello Window\nkind: windowed\nidentifier: com.example.HelloWindow\nicon: icon.png\n#{"installers: #{installers}\n" if installers}")
      File.binwrite(File.join(root, "icon.png"), ICON)
      root
    end

    ICON = Fledge::Png.new(width: 1024, height: 1024, pixels: ([40, 80, 160, 255] * (1024 * 1024)).pack("C*")).encode
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
    lib/ruby/gems/4.0.0/specifications
    lib/ruby/gems/4.0.0/specifications/csv-3.3.5.gemspec
    lib/ruby/gems/4.0.0/specifications/default
    lib/ruby/gems/4.0.0/specifications/default/json-2.18.0.gemspec
    lib/ruby/stdlib.rb
  ].freeze

  def assemble(dir, app_root, platform: LINUX, runtime: FakeRuntime.write(dir, platform), app_files: {}, files: [], makensis: nil)
    out = File.join(dir, "dist")
    Fledge::Assembly.new(app: Fledge::App.at(app_root), platform:, runtime:, out:, app_files:, files:, makensis:).call
  end

  # What a runtime keeps for installers, in its installer folder.
  APPIMAGE_RUNTIME = Fledge::Entry.file("installer/appimage-runtime", "\x7FELF runtime".b, mode: 0o755)

  def entries(archive)
    found = {}
    Fledge::TarGz.each_entry(archive) { |entry| found[entry.path] = entry }
    found
  end

  def test_the_runtime_and_app_land_in_a_folder_and_an_archive_with_the_launcher_renamed
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, "helper.rb"), "")

      archive = assemble(dir, app)

      assert_equal File.join(dir, "dist", "Hello-x86_64-linux.tar.gz"), archive
      folder = File.join(dir, "dist", "Hello-x86_64-linux")
      assert_equal %w[Hello app fledge.cfg lib], Dir.children(folder).sort
      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Hello"))
      assert_equal "puts 'hi'\n", File.read(File.join(folder, "app/main.rb"))
      assert_equal "ruby", File.readlink(File.join(folder, "lib/current")) unless Gem.win_platform?

      found = entries(archive)
      expected = ["", "/Hello", "/app", "/app/helper.rb", "/app/main.rb", "/fledge.cfg", *RUNTIME_FILES.map { |path| "/#{path}" }]
      assert_equal expected.map { |path| "Hello-x86_64-linux#{path}" }.sort, found.keys.sort
      assert_equal 0o755, found.fetch("Hello-x86_64-linux/Hello").mode
      assert_equal :symlink, found.fetch("Hello-x86_64-linux/lib/current").type
    end
  end

  # The launcher reads fledge.cfg, beside it, to learn what to run
  # (runtime/launcher/config.c).
  def test_fledge_cfg_names_the_entry_point_and_a_gemfile
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      hello = FakeApp.write(dir)
      assemble(dir, hello)
      assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = main.rb\n",
        File.read(File.join(dir, "dist/Hello-x86_64-linux/fledge.cfg"))

      project = FakeProject.write(dir, name: "my_cool_app")
      assemble(dir, File.join(project, "exe/my_cool_app"))
      assert_equal "# Written by fledge build: what this app's program runs (ADR 005).\nentry = exe/my_cool_app\ngemfile = Gemfile\n",
        File.read(File.join(dir, "dist/MyCoolApp-x86_64-linux/fledge.cfg"))
    end
  end

  def test_app_files_replace_or_join_the_projects_and_files_join_the_runtimes
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, "hello.gemspec.txt"), "original\n")
      gem = Fledge::Entry.file("lib/ruby/gems/4.0.0/gems/foo-1.0.0/lib/foo.rb", "# foo\n")

      archive = assemble(dir, app, app_files: { "hello.gemspec.txt" => "evaluated\n", ".bundle/config" => "---\n" },
        files: [gem, Fledge::Entry.file("lib/ruby/gems/4.0.0/build_info/foo-1.0.0.info", "--with-foo\n")])

      folder = File.join(dir, "dist", "Hello-x86_64-linux")
      assert_equal "evaluated\n", File.read(File.join(folder, "app/hello.gemspec.txt"))
      assert_equal "---\n", File.read(File.join(folder, "app/.bundle/config"))
      assert_equal "# foo\n", File.read(File.join(folder, gem.path))
      found = entries(archive)
      %w[app/.bundle lib/ruby/gems/4.0.0/gems lib/ruby/gems/4.0.0/gems/foo-1.0.0/lib lib/ruby/gems/4.0.0/build_info].each do |parent|
        assert_equal :directory, found.fetch("Hello-x86_64-linux/#{parent}").type, parent
      end
      assert_equal 1, found.keys.count("Hello-x86_64-linux/lib/ruby/gems/4.0.0")
    end
  end

  def test_an_added_file_may_not_replace_the_runtimes_and_nothing_is_left
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, LINUX)
      clash = Fledge::Entry.file("lib/ruby/gems/4.0.0/specifications/csv-3.3.5.gemspec", "# mine\n")

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:, files: [clash]) }

      assert_equal "#{clash.path} is in #{runtime} already, so the build can't add its own", error.message
      assert_empty Dir.children(File.join(dir, "dist"))
    end
  end

  # Windows' layout differs from Unix's (Ruby's own tree in ruby\, not
  # lib/ beside the launcher), but assembly hardly cares: it renames
  # launcher.exe, with the app's version information in it, and copies the
  # rest as the runtime holds it, but for launcherw.exe, which a console
  # app does not run.
  def test_a_windows_app_lands_in_a_folder_and_a_zip_with_the_exe_renamed
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, WINDOWS, extra: [Fledge::Entry.file("ruby/bin/x64-ucrt-ruby400.dll", "MZ", mode: 0o755)])

      app = FakeApp.write(dir)
      archive = assemble(dir, app, platform: WINDOWS, runtime:)

      assert_equal File.join(dir, "dist", "Hello-x64-mingw-ucrt.zip"), archive
      folder = File.join(dir, "dist", "Hello-x64-mingw-ucrt")
      assert_equal %w[Hello.exe app fledge.cfg ruby], Dir.children(folder).sort
      program = Fledge::WindowsProgram.new(File.binread(File.join(folder, "Hello.exe")))
      assert_equal Fledge::WindowsProgram::CONSOLE, program.subsystem
      assert_equal [[16, 1, 1033], [24, 1, 1033]], program.resources.keys
      members = ZipReader.read(archive).to_h { |member| [member.name, member] }
      assert_includes members.keys, "Hello-x64-mingw-ucrt/ruby/bin/x64-ucrt-ruby400.dll"
      assert_includes members.keys, "Hello-x64-mingw-ucrt/fledge.cfg"
      assert_equal File.binread(File.join(folder, "Hello.exe")), members.fetch("Hello-x64-mingw-ucrt/Hello.exe").data
      assert_equal File.binread(File.join(app, "main.rb")), members.fetch("Hello-x64-mingw-ucrt/app/main.rb").data
      refute_path_exists File.join(dir, "dist", "Hello-x64-mingw-ucrt.tar.gz")
    end
  end

  # A windowed app runs launcherw.exe, a GUI program, renamed, with its
  # identity; fledge.cfg names its identifier for the launcher's
  # AppUserModelID.
  def test_a_windowed_windows_app_runs_the_gui_launcher
    Dir.mktmpdir do |dir|
      app = WindowedApp.write(dir)
      assemble(dir, app, platform: WINDOWS)

      folder = File.join(dir, "dist", "Hello Window-x64-mingw-ucrt")
      assert_equal ["Hello Window.exe", "app", "fledge.cfg", "ruby"], Dir.children(folder).sort
      program = Fledge::WindowsProgram.new(File.binread(File.join(folder, "Hello Window.exe")))
      assert_equal Fledge::WindowsProgram::GUI, program.subsystem
      assert_includes program.resources.keys, [14, 32_512, 1033]
      assert_includes File.read(File.join(folder, "fledge.cfg")), "\nidentifier = com.example.HelloWindow\n"
    end
  end

  def test_a_windowed_app_needs_a_runtime_with_a_windowed_launcher
    Dir.mktmpdir do |dir|
      runtime = File.join(dir, "old.tar.gz")
      Fledge::TarGz.write(runtime) { |tar| tar.add(Fledge::Entry.file("top/launcher.exe", FakeRuntime::WINDOWS_CONSOLE, mode: 0o755)) }

      error = assert_raises(Fledge::Error) { assemble(dir, WindowedApp.write(dir), platform: WINDOWS, runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcherw.exe", error.message
    end
  end

  # A windowed app on macOS is an .app bundle: the launcher in MacOS, the
  # runtime and the app in Resources, linked from MacOS where the launcher
  # and Ruby look for them, an Info.plist and icon, and a seal, with the
  # launcher signed for them.
  def test_a_windowed_macos_app_is_a_signed_bundle
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, MACOS, launcher: Programs.macho, extra: [Fledge::Entry.file("libexec/cert.pem", "pem")])
      archive = assemble(dir, WindowedApp.write(dir), platform: MACOS, runtime:)

      folder = File.join(dir, "dist", "Hello Window-arm64-darwin")
      contents = File.join(folder, "Hello Window.app", "Contents")
      assert_equal ["Hello Window.app"], Dir.children(folder)
      assert_equal %w[Info.plist MacOS Resources _CodeSignature], Dir.children(contents).sort
      assert_equal ["Hello Window", "app", "fledge.cfg", "lib", "libexec"], Dir.children(File.join(contents, "MacOS")).sort
      %w[app fledge.cfg lib libexec].each do |name|
        assert_equal "../Resources/#{name}", File.readlink(File.join(contents, "MacOS", name)), name unless Gem.win_platform?
      end
      assert_equal ["Hello Window.icns", "app", "fledge.cfg", "lib", "libexec"], Dir.children(File.join(contents, "Resources")).sort
      plist = File.read(File.join(contents, "Info.plist"))
      assert_includes plist, "<key>CFBundleIdentifier</key>\n\t<string>com.example.HelloWindow</string>"
      assert_includes plist, "<key>CFBundleExecutable</key>\n\t<string>Hello Window</string>"
      seal = File.read(File.join(contents, "_CodeSignature", "CodeResources"))
      assert_includes seal, "<key>Resources/app/main.rb</key>"
      assert_includes seal, "<key>MacOS/lib</key>"
      refute_includes seal, "<key>MacOS/Hello Window</key>"

      launcher = File.binread(File.join(contents, "MacOS", "Hello Window"))
      expected = Fledge::AdHocSignature.new(identifier: "com.example.HelloWindow", info_plist: plist, code_resources: seal).sign(Programs.macho)
      assert_equal expected, launcher
      assert_equal 0o755, entries(archive).fetch("Hello Window-arm64-darwin/Hello Window.app/Contents/MacOS/Hello Window").mode
      assert_equal :symlink, entries(archive).fetch("Hello Window-arm64-darwin/Hello Window.app/Contents/MacOS/lib").type
    end
  end

  # A windowed app on Linux keeps the folder, with a desktop entry beside
  # the program and its icons in the hicolor theme's folders.
  def test_a_windowed_linux_app_has_a_desktop_entry_and_icons
    Dir.mktmpdir do |dir|
      assemble(dir, WindowedApp.write(dir))

      folder = File.join(dir, "dist", "Hello Window-x86_64-linux")
      assert_equal ["Hello Window", "app", "com.example.HelloWindow.desktop", "fledge.cfg", "lib", "share"], Dir.children(folder).sort
      assert_includes File.read(File.join(folder, "com.example.HelloWindow.desktop")), "Exec=\"Hello Window\"\n"
      assert_path_exists File.join(folder, "share/icons/hicolor/512x512/apps/com.example.HelloWindow.png")
      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(folder, "Hello Window"))
    end
  end

  # A windowed app gets its platform's installer by default (ADR 009),
  # written beside its archive from the same entries and the runtime's
  # installer folder, which neither the folder nor the archive holds.
  def test_a_windowed_linux_app_gets_an_appimage_from_the_runtimes_installer_folder
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, LINUX, extra: [Fledge::Entry.directory("installer"), APPIMAGE_RUNTIME])
      app = Fledge::App.at(WindowedApp.write(dir, installers: nil))
      assembly = Fledge::Assembly.new(app:, platform: LINUX, runtime:, out: File.join(dir, "dist"))
      archive = assembly.call

      image = File.join(dir, "dist", "Hello Window-x86_64-linux.AppImage")
      assert_equal [image], assembly.installers
      assert_equal APPIMAGE_RUNTIME.content, File.binread(image, APPIMAGE_RUNTIME.content.bytesize)
      refute_path_exists File.join(dir, "dist", "Hello Window-x86_64-linux", "installer")
      assert(entries(archive).keys.none? { |path| path.include?("installer") })
    end
  end

  def test_a_windowed_macos_app_gets_a_disk_image_of_its_bundle
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.write(dir, MACOS, launcher: Programs.macho)
      app = Fledge::App.at(WindowedApp.write(dir, installers: nil))
      assembly = Fledge::Assembly.new(app:, platform: MACOS, runtime:, out: File.join(dir, "dist"))
      assembly.call

      image = File.join(dir, "dist", "Hello Window-arm64-darwin.dmg")
      assert_equal [image], assembly.installers
      hfs = DiskImages::Hfs.new(DiskImages.udif(image)[:volume])
      bundle = File.join(dir, "dist", "Hello Window-arm64-darwin", "Hello Window.app", "Contents")
      assert_equal File.binread(File.join(bundle, "MacOS", "Hello Window")), hfs.items.fetch("Hello Window.app/Contents/MacOS/Hello Window")[:content]
      assert_equal File.read(File.join(bundle, "_CodeSignature", "CodeResources")),
        hfs.items.fetch("Hello Window.app/Contents/_CodeSignature/CodeResources")[:content]
      assert_equal "/Applications", hfs.items.fetch("Applications")[:content]
    end
  end

  def test_an_nsis_installer_without_makensis_fails_and_leaves_nothing
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { assemble(dir, WindowedApp.write(dir, installers: "[nsis]"), platform: WINDOWS) }

      assert_includes error.message, "an NSIS installer needs makensis"
      assert_empty Dir.glob(File.join(dir, "dist", "*"))
    end
  end

  def test_a_build_without_the_runtimes_installer_files_fails_and_leaves_nothing
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { assemble(dir, WindowedApp.write(dir, installers: nil)) }

      assert_includes error.message, "the runtime has no installer/appimage-runtime"
      assert_empty Dir.glob(File.join(dir, "dist", "*"))
    end
  end

  # A console app on macOS stays a folder with the launcher as it came.
  def test_a_console_macos_app_is_a_folder
    Dir.mktmpdir do |dir|
      assemble(dir, FakeApp.write(dir), platform: MACOS)

      assert_equal FakeRuntime::LAUNCHER, File.read(File.join(dir, "dist", "Hello-arm64-darwin", "Hello"))
    end
  end

  def test_a_windows_runtime_without_launcher_exe_is_refused
    Dir.mktmpdir do |dir|
      runtime = File.join(dir, "unix-launcher.tar.gz")
      Fledge::TarGz.write(runtime) { |tar| tar.add(Fledge::Entry.file("top/launcher", "", mode: 0o755)) }

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), platform: WINDOWS, runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcher.exe", error.message
      assert_empty Dir.children(File.join(dir, "dist"))
    end
  end

  def test_a_symlink_in_an_app_for_windows_is_refused_and_nothing_is_left
    skip "symlinks need privileges on Windows" if Gem.win_platform?

    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.symlink("main.rb", File.join(app, "link.rb"))

      error = assert_raises(Fledge::Error) { assemble(dir, app, platform: WINDOWS) }

      assert_equal "Hello-x64-mingw-ucrt/app/link.rb is a symbolic link, which a .zip for Windows cannot hold. " \
        "Replace it with what it points to.", error.message
      assert_empty Dir.children(File.join(dir, "dist"))
    end
  end

  def test_the_launcher_stays_executable_in_the_archive_whatever_the_disk_keeps
    Dir.mktmpdir do |dir|
      archive = assemble(dir, FakeApp.write(dir))

      assert_equal 0o755, entries(archive).fetch("Hello-x86_64-linux/Hello").mode
    end
  end

  def test_a_build_replaces_the_previous_one
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
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      runtime = FakeRuntime.write(dir, LINUX)
      out = File.join(app, "dist")
      2.times { Fledge::Assembly.new(app: Fledge::App.at(app), platform: LINUX, runtime:, out:).call }

      assert_equal ["main.rb"], Dir.children(File.join(out, "Hello-x86_64-linux/app"))
    end
  end

  def test_an_app_named_like_a_runtime_folder_is_refused_and_nothing_is_left
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir, "lib")
      File.write(File.join(app, "fledge.yml"), "name: LIB\n")

      error = assert_raises(Fledge::Error) { assemble(dir, app) }

      assert_equal "an app named LIB would collide with the runtime's lib. Give it another name.", error.message
      assert_empty Dir.children(File.join(dir, "dist"))
    end
  end

  def test_an_app_named_app_or_fledge_cfg_is_refused
    Dir.mktmpdir do |dir|
      { "App" => "its own app folder", "fledge.cfg" => "the file that says what it runs" }.each do |name, what|
        app = FakeApp.write(dir, "x#{name.size}")
        File.write(File.join(app, "fledge.yml"), "name: #{name}\n")

        error = assert_raises(Fledge::Error, name) { assemble(dir, app) }
        assert_equal "an app named #{name} would collide with #{what}. Give it another name.", error.message
      end
    end
  end

  def test_an_entry_point_fledge_cfg_cannot_hold_is_refused
    Dir.mktmpdir do |dir|
      app = FakeApp.write(dir)
      File.write(File.join(app, " spaced.rb"), "")

      error = assert_raises(Fledge::Error) { assemble(dir, File.join(app, " spaced.rb")) }
      assert_equal "\" spaced.rb\" can't be an app's program or Gemfile: its name begins or ends with a space, or holds a line break",
        error.message
    end
  end

  def test_a_runtime_without_a_launcher_is_refused
    Dir.mktmpdir do |dir|
      runtime = File.join(dir, "empty.tar.gz")
      Fledge::TarGz.write(runtime) { |tar| tar.add(Fledge::Entry.directory("top")) }

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcher", error.message
    end
  end

  def test_a_runtime_with_two_top_folders_is_refused
    Dir.mktmpdir do |dir|
      runtime = File.join(dir, "two.tar.gz")
      Fledge::TarGz.write(runtime) do |tar|
        tar.add(Fledge::Entry.file("a/launcher", "", mode: 0o755))
        tar.add(Fledge::Entry.file("b/x", ""))
      end

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it holds both a/ and b", error.message
    end
  end

  def test_a_runtime_holding_an_app_or_a_fledge_cfg_is_refused
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
