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
  # it. NSIS, the installer Tauri's bundler writes by default, compiles
  # with +makensis+, which runs on Linux and macOS too, so any computer
  # still builds every platform (ADR 001; ADR 009).
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
  # then the folder if it is empty. It compresses with zlib, whose NSIS
  # module, unlike LZMA's (CPL-1.0), asks nothing of whoever ships it
  # (decision 8).
  #
  # Use it through Fledge::Assembly, which hands it every entry of a
  # Windows app's folder, then calls #finish with the runtime's NSIS.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   setup = Fledge::Nsis.new(identity:, folder: "dist/MyApp-x64-mingw-ucrt", to: "dist/MyApp-x64-mingw-ucrt-setup.exe",
  #     makensis: "/home/you/.cache/fledge/makensis/makensis")
  #   setup.add(Fledge::Entry.file("MyApp.exe", program, mode: 0o755))
  #   setup.finish(kit) # => "dist/MyApp-x64-mingw-ucrt-setup.exe"
  #--
  # SPDX-SnippetEnd
  #++
  class Nsis
    # The registry key, under HKCU, whose subkeys list installed apps.
    UNINSTALL_KEY = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'

    # The uninstaller's name in the app's folder, as Tauri names it.
    UNINSTALLER = "uninstall.exe"

    # Creates the installer of the app whose Fledge::Identity is +identity+.
    #
    # [folder] The built app's folder, which the installer copies.
    # [to] The installer's path.
    # [makensis] The path of the NSIS compiler to run.
    def initialize(identity:, folder:, to:, makensis:)
      @identity = identity
      @folder = folder
      @to = to
      @makensis = makensis
      @files = [] # : Array[String]
      @folders = [] # : Array[String]
      @size = 0
    end

    # Notes +entry+, whose path is relative to the app's folder, as one
    # the installer installs and the uninstaller removes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   setup.add(Fledge::Entry.directory("ruby"))
    #--
    # SPDX-SnippetEnd
    #++
    def add(entry)
      if entry.type == :directory
        @folders << entry.path
      else
        @files << entry.path
        @size += entry.content.bytesize
      end
    end

    # The installer's NSIS script.
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
      Script.new(identity: @identity, folder: @folder, to: @to, files: @files, folders: @folders, size: @size).text(icon:)
    end

    # Compiles the installer with the NSIS in +kit+, the runtime's
    # installer files by path (<tt>nsis/Stubs</tt>, <tt>nsis/Plugins</tt>,
    # <tt>nsis/Include</tt>, and <tt>nsis/Contrib</tt>), and returns its
    # path. Raises Fledge::Error when the runtime has no NSIS, or makensis
    # cannot run or refuses the script.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   setup.finish(kit) # => "dist/MyApp-x64-mingw-ucrt-setup.exe"
    #--
    # SPDX-SnippetEnd
    #++
    def finish(kit)
      Dir.mktmpdir("fledge-nsis") do |work|
        nsis = File.join(work, "nsis")
        kit.each { |path, entry| entry.with(path:).write_into(work) if path.start_with?("nsis/") }
        raise Error, "the runtime has no installer/nsis, which runtimes carry from Fledge 0.0.1.pre.7 on" unless File.directory?(nsis)

        icon = @identity.icon
        icon_path = icon && File.join(work, "app.ico")
        File.binwrite(icon_path, icon.ico) if icon && icon_path
        script_path = File.join(work, "setup.nsi")
        File.binwrite(script_path, "\uFEFF#{script(icon: icon_path)}")
        compile(script_path, nsis)
      end
      @to
    end

    # Removes what the installer has written, after a build that failed.
    def abort
      FileUtils.rm_f(@to)
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
      command = [@makensis, "-V2", "-NOCD", "-NOCONFIG", "-INPUTCHARSET", "UTF8", Nsis.host_path(script_path)]
      output, status = Open3.capture2e({ "NSISDIR" => Nsis.host_path(nsis) }, *command)
      return if status.success? && File.file?(@to)

      FileUtils.rm_f(@to)
      raise Error, "makensis could not write #{File.basename(@to)}:\n#{output.strip}"
    rescue SystemCallError => e
      raise Error, "makensis could not run (#{e.message})"
    end
  end
end
