# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require "open3"

# What the tests of Fledge::Assembly share: test/assembly_test.rb's, with
# fake runtimes alone, and test/integration/assembly_tools_test.rb's,
# with the tools of the platform the app is for.
module AssemblyHelpers
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
end
