# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
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
  # Start menu carries the AppUserModelID the app gives itself (ADR 008,
  # section 3), and only an installer makes one. People also expect an app
  # they install to be in Settings' list of apps, where they can remove
  # it. NSIS is the installer Tauri's bundler writes by default, and on
  # Windows, where Windows apps are built (ADR 010), Tauri runs NSIS's own
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
  # runtime and naming it in the app's notices, which the installer holds
  # (ADR 010).
  #
  # Use it through Fledge::Installers, once the app's folder is built.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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

    # Creates the installer of the app whose Fledge::Identity is +identity+.
    #
    # [folder] The built app's folder, which the installer copies.
    # [to] The installer's path.
    def initialize(identity:, folder:, to:)
      @identity = identity
      @folder = folder
      @to = to
    end

    # The installer's NSIS script, which installs every file and folder in
    # the app's folder, and whose uninstaller removes exactly those.
    #
    # [icon] The path of the app's icon as an <tt>.ico</tt>, or +nil+ for
    #        NSIS's own.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   setup.script(icon: nil).lines.first # => "Unicode true\n"
    #--
    # SPDX-SnippetEnd
    #++
    def script(icon:)
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
      Script.new(identity: @identity, folder: @folder, to: @to, files:, folders:, size:).text(icon:)
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
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   setup.write(tools) # => "dist/MyApp-x64-mingw-ucrt-setup.exe"
    #--
    # SPDX-SnippetEnd
    #++
    def write(tools)
      nsis = tools && File.join(tools, "nsis")
      raise Error, "the runtime has no tools/nsis, which Windows runtimes carry from Fledge 0.0.1.pre.8 on" unless nsis && File.file?(File.join(nsis, MAKENSIS))

      Dir.mktmpdir("fledge-nsis") do |work|
        script_path = File.join(work, "setup.nsi")
        File.binwrite(script_path, "\uFEFF#{script(icon: @identity.icon&.file('ico'))}")
        compile(script_path, nsis)
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
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
      raise Error, "makensis could not write #{File.basename(@to)}:\n#{output.strip}"
    rescue SystemCallError => e
      raise Error, "makensis could not run (#{e.message})"
    end
  end
end
