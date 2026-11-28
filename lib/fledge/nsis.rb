# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "open3"
require "tmpdir"
require_relative "entry"
require_relative "error"
require_relative "nsis/script"

module Fledge
  # A Windows app's setup program: an NSIS installer.
  #
  # Windows shows an app's notifications only when a shortcut in the
  # Start menu carries the AppUserModelID the app gives itself, and only an
  # installer makes one. People also expect an app
  # they install to be in Settings' list of apps, where they can remove
  # it. NSIS is the installer Tauri's bundler writes by default, and on
  # Windows, where Windows apps are built, Tauri runs NSIS's own
  # release, as Fledge does: the Windows runtime carries it in its tools
  # folder, which no app holds.
  #
  # This class writes the installer as Tauri's <tt>installer.nsi</tt> does
  # for its default, per-user mode (<tt>currentUser</tt>), with what
  # Fledge's apps need and none of Tauri's own plugin: it needs no
  # administrator (<tt>RequestExecutionLevel user</tt>) and installs into
  # <tt>%LOCALAPPDATA%\Programs\NAME</tt>, Windows' folder for programs one
  # person installs (FOLDERID_UserProgramFiles), as electron-builder's
  # per-user installers do; it makes a Start menu shortcut and sets its
  # <tt>System.AppUserModel.ID</tt> through IPropertyStore, with the COM
  # headers NSIS ships, as Tauri's +SetLnkAppUserModelId+ macro does; it
  # offers a desktop shortcut, unchecked, on its last page, and makes none
  # when run silently (<tt>/S</tt>); it registers an uninstaller under the
  # identifier in <tt>HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall</tt>;
  # and the setup program carries the app's icon and version information.
  # A new version runs the old version's uninstaller first, as
  # electron-builder's do, so files a version no longer has do not linger;
  # the uninstaller deletes exactly the files and folders it installed,
  # then the folder if it is empty. It compresses with LZMA, solid, NSIS's
  # default and Tauri's; NSIS's LZMA module is under the Common Public
  # License, whose request that a binary say where its source is
  # available Fledge meets by publishing NSIS's source beside each Windows
  # runtime and naming it in the app's notices, which the installer holds.
  #
  # Use it through Fledge::Installers, once the app's folder is built.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   setup = Fledge::Nsis.new(identity:, folder: "dist/MyApp-x64-mingw-ucrt", to: "dist/MyApp-x64-mingw-ucrt-setup.exe")
  #   setup.write(tools) # => "dist/MyApp-x64-mingw-ucrt-setup.exe"
  #--
  # SPDX-SnippetEnd
  #++
  class Nsis
    # The registry key, under HKCU, whose subkeys list installed apps.
    UNINSTALL_KEY = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'

    # The uninstaller's name in the app's folder, as Tauri names it.
    UNINSTALLER = "uninstall.exe"

    # makensis's path in the runtime's NSIS: the release's own Windows
    # program, in its Bin folder, beside the zlib1.dll it loads.
    MAKENSIS = File.join("Bin", "makensis.exe")

    # The width, in pixels, of the bitmap Modern UI's welcome and finish
    # pages lay out down their left side: that of NSIS's own image, the
    # default of +MUI_WELCOMEFINISHPAGE_BITMAP+.
    SIDEBAR_WIDTH = 164

    # The height of that bitmap, in pixels.
    SIDEBAR_HEIGHT = 314

    # A byte order mark, U+FEFF, which tells a Unicode installer that a
    # text file is UTF-8, and which a license text saved by a Windows
    # editor may already begin with.
    BOM = [0xFEFF].pack("U").freeze

    # The file in the app's folder that says what its program runs, and
    # which Visual C++ runtime DLLs its launcher looks for.
    CONFIG = "fledge.cfg"

    # Where the setup program of an app built with <tt>windows: {
    # visual_c_runtime: central }</tt> downloads Microsoft's Visual C++
    # Redistributable from, for each Windows platform: Microsoft's
    # permanent links to the latest supported one ("Latest supported
    # Visual C++ Redistributable downloads"), the ones the launcher's
    # message names.
    REDISTRIBUTABLES = {
      "x64-mingw-ucrt" => "https://aka.ms/vc14/vc_redist.x64.exe",
      "aarch64-mingw-ucrt" => "https://aka.ms/vc14/vc_redist.arm64.exe",
    }.freeze

    # Creates the installer of the app whose Fledge::Identity is +identity+.
    #
    # [folder] The built app's folder, which the installer copies.
    # [platform] The Fledge::Platform the app is built for.
    # [to] The installer's path.
    # [signing] The Fledge::WindowsSigning or Fledge::SignCommand that
    #           makensis signs the installer and its uninstaller with, or
    #           +nil+.
    # [license] The app's license text, which a page shows before the
    #           install, or +nil+ for no such page.
    # [redistributable] Where the setup program downloads the Visual C++
    #                   Redistributable from, when the app's DLLs need
    #                   it: +nil+ for the platform's in REDISTRIBUTABLES,
    #                   which fledge build always gives; a test gives a
    #                   server of its own.
    def initialize(identity:, folder:, platform:, to:, signing: nil, license: nil, redistributable: nil)
      @identity = identity
      @folder = folder
      @to = to
      @signing = signing
      @license = license
      @redistributable = redistributable || REDISTRIBUTABLES.fetch(platform.name) { raise Error, "an nsis installer is for Windows, and #{platform.name} is not" }
    end

    # The bitmap down the left side of the setup program's finish page:
    # plain white, the page's own color, as a 24-bit bitmap of
    # SIDEBAR_WIDTH by SIDEBAR_HEIGHT pixels. Fledge reads no image
    # format, so it
    # cannot draw the app's icon there; a script that sets no bitmap
    # gets the one NSIS ships.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Nsis.sidebar_bitmap.bytesize # => 154542
    #--
    # SPDX-SnippetEnd
    #++
    def self.sidebar_bitmap
      pixels = "\xFF".b * (3 * SIDEBAR_WIDTH * SIDEBAR_HEIGHT)
      file = ["BM", 54 + pixels.bytesize, 0, 0, 54].pack("a2Vv2V")
      info = [40, SIDEBAR_WIDTH, SIDEBAR_HEIGHT, 1, 24, 0, pixels.bytesize, 2835, 2835, 0, 0].pack("Vl<2v2V2l<2V2")
      file + info + pixels
    end

    # +text+ as the license page reads a text file: with a UTF-8 byte
    # order mark, which a Unicode installer needs to read it as UTF-8, as
    # Tauri's bundler writes one (<tt>nsis/mod.rs</tt>), and with DOS line
    # endings, which NSIS's LicenseData asks for (its manual, 4.8.1.26).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Nsis.license_text("MIT\n").bytes.first(3) # => [0xEF, 0xBB, 0xBF]
    #--
    # SPDX-SnippetEnd
    #++
    def self.license_text(text)
      "#{BOM}#{text.gsub(/\r?\n/, "\r\n")}"
    end

    # The installer's NSIS script, which installs every file and folder in
    # the app's folder, and whose uninstaller removes exactly those.
    #
    # [icon] The path of the app's icon as an <tt>.ico</tt>, or +nil+ for
    #        NSIS's own.
    # [sidebar] The path of the bitmap down the left side of the finish
    #           page, as Nsis.sidebar_bitmap makes it, or +nil+ for
    #           NSIS's own.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   setup.script(icon: nil).lines.first # => "Unicode true\n"
    #--
    # SPDX-SnippetEnd
    #++
    def script(icon:, license: nil, sidebar: nil)
      files = [] # : Array[String]
      folders = [] # : Array[String]
      size = 0
      Dir.glob("**/*", File::FNM_DOTMATCH, base: @folder).sort.each do |path|
        next if File.basename(path) == "."

        full = File.join(@folder, path)
        if File.directory?(full)
          folders << path
        else
          files << path
          size += File.size(full)
        end
      end
      Script.new(identity: @identity, folder: @folder, to: @to, files:, folders:, size:, signing: @signing&.command_line,
        visual_c_runtime:, redistributable: @redistributable).text(icon:, license:, sidebar:)
    end

    # The DLLs of Microsoft's Visual C++ runtime that the app's gems need
    # and the app does not carry, which its fledge.cfg names for the
    # launcher to look for in System32 (Assembly.launch_config): those of
    # an app built with <tt>windows: { visual_c_runtime: central }</tt>,
    # and none for any other. Reading them there keeps the setup program
    # true to the folder it installs, one built with --from included.
    private def visual_c_runtime
      config = File.join(@folder, CONFIG)
      return [] unless File.file?(config)

      File.binread(config)[/^visual_c_runtime = (.+)$/, 1].to_s.split
    end

    # Compiles the installer with the NSIS in +tools+, the runtime's
    # tools folder: NSIS's own release, its makensis and the stubs,
    # plug-ins, headers, and Modern UI it compiles from, in
    # <tt>tools/nsis</tt>. Returns the installer's path. Raises
    # Fledge::Error when the runtime has no NSIS, or makensis cannot run or
    # refuses the script.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   setup.write(tools) # => "dist/MyApp-x64-mingw-ucrt-setup.exe"
    #--
    # SPDX-SnippetEnd
    #++
    def write(tools)
      nsis = tools && File.join(tools, "nsis")
      raise Error, "the runtime has no tools/nsis, which Windows runtimes carry from Fledge 0.0.1.pre.8 on" unless nsis && File.file?(File.join(nsis, MAKENSIS))

      work = Dir.mktmpdir("fledge-nsis")
      begin
        copy = File.join(work, "nsis")
        FileUtils.cp_r(nsis, copy)
        script_path = File.join(work, "setup.nsi")
        license = @license && File.join(work, "license.txt")
        File.binwrite(license, Nsis.license_text(@license.to_s)) if license
        sidebar = File.join(work, "sidebar.bmp")
        File.binwrite(sidebar, Nsis.sidebar_bitmap)
        File.binwrite(script_path, "\uFEFF#{script(icon: @identity.icon&.file('ico'), license:, sidebar:)}")
        compile(script_path, copy)
      ensure
        # On Windows on ARM, the x86 emulator's cache service (XtaCache)
        # keeps makensis.exe open for a while after it exits, so the copy
        # it ran from may not delete yet; it is the system's temporary
        # folder's to clear, never the build's own.
        FileUtils.rm_rf(work)
      end
      @to
    end

    # +path+ as makensis on this computer reads it: absolute, with
    # Windows' backslashes on Windows, where makensis finds no files for
    # a wildcard after forward slashes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Nsis.host_path("dist/MyApp/*") # => "/home/you/project/dist/MyApp/*", or "C:\\project\\dist\\MyApp\\*"
    #--
    # SPDX-SnippetEnd
    #++
    def self.host_path(path)
      full = File.expand_path(path)
      separator = File::ALT_SEPARATOR
      separator ? full.tr("/", separator) : full
    end

    private def compile(script_path, nsis)
      command = [File.join(nsis, MAKENSIS), "-V2", "-NOCD", "-NOCONFIG", "-INPUTCHARSET", "UTF8", Nsis.host_path(script_path)]
      output, status = Open3.capture2e({ "NSISDIR" => Nsis.host_path(nsis) }, *command)
      return if status.success? && File.file?(@to)

      FileUtils.rm_f(@to)
      raise Error, "#{signing_failure(output)}makensis could not write #{File.basename(@to)}:\n#{output.strip}"
    rescue SystemCallError => e
      raise Error, "makensis could not run (#{e.message})"
    end

    # The line that names the file the signing command failed on, from
    # makensis's +output+, which says "UninstFinalize command returned"
    # for the uninstaller and "Finalize command returned" for the setup
    # program (NSIS's run_postbuild_cmds, Source/build.cpp), or "" when
    # signing did not fail.
    private def signing_failure(output)
      found = output.match(/\b(Uninst)?Finalize command returned (-?\d+)/)
      return "" unless found

      file = found[1] ? "the uninstaller of #{File.basename(@to)}" : File.basename(@to)
      "the signing command failed on #{file} (exit #{found[2]})\n"
    end
  end
end
