# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/assembly"
require_relative "../support/disk_images"
require "open3"

# Fledge::Assembly with the tools of the platform the app is for, on that
# platform (ADR 010): on a Mac, codesign, plutil, and hdiutil; on
# Windows, the real Windows runtime's launchers and rcedit, and Windows'
# own reading of a program's version information. test/assembly_test.rb
# covers what fake runtimes alone show.
class AssemblyToolsTest < Minitest::Test
  include AssemblyHelpers

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
      assert_equal %w[Hello.exe app fledge.cfg ruby], Dir.children(folder).sort
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
      assert_equal ["Hello Window.exe", "app", "fledge.cfg", "ruby"], Dir.children(folder).sort
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

  # On Windows each program is its own launcher: the GUI one for the
  # windowed program, the console one for the rest, each with its own
  # name in its version information.
  def test_on_windows_each_program_is_its_kinds_launcher
    windows!
    Dir.mktmpdir do |dir|
      assemble(dir, Programs.write(dir), platform: WINDOWS)

      folder = File.join(dir, "dist", "Game-x64-mingw-ucrt")
      assert_equal ["Play Game.exe", "app", "fledge.cfg", "game-cli.exe", "ruby", "tui.exe"], Dir.children(folder).sort
      assert_equal [2, 3, 3], ["Play Game.exe", "game-cli.exe", "tui.exe"].map { |program| subsystem(File.join(folder, program)) }
      assert_equal ["Play Game", "game-cli", "tui"],
        ["Play Game.exe", "game-cli.exe", "tui.exe"].map { |program| version_info(File.join(folder, program)).fetch("FileDescription") }
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

  def test_a_windows_runtime_without_launcher_exe_is_refused
    windows!
    Dir.mktmpdir do |dir|
      runtime = FakeRuntime.pack(File.join(dir, "unix-launcher.tar.gz"), "top", [Fledge::Entry.file("launcher", "", mode: 0o755)])

      error = assert_raises(Fledge::Error) { assemble(dir, FakeApp.write(dir), platform: WINDOWS, runtime:) }
      assert_equal "#{runtime} is not a Fledge runtime: it has no launcher.exe", error.message
      assert_empty left_in(dir)
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
end
