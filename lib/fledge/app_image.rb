# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tempfile"
require_relative "entry"
require_relative "error"
require_relative "squashfs"

module Fledge
  # A Linux app as one file a person downloads and runs on any
  # distribution: an AppImage.
  #
  # A <tt>.tar.gz</tt> has to be unpacked, and a package for one family
  # of distributions misses the rest. An AppImage is a program (its
  # runtime) followed by a file system that holds the app; run, the
  # runtime mounts the file system with FUSE and runs its +AppRun+, or,
  # where there is no FUSE, extracts it and runs that (ADR 009). Tauri's
  # bundler writes one with linuxdeploy and appimagetool, which run only
  # on Linux; electron-builder writes its own on macOS too. Fledge writes
  # one on any computer (ADR 001).
  #
  # This class lays the AppImage's file system out as AppImage's
  # specification lays out an AppDir: the built app's folder, which
  # already has the desktop entry at its top (ADR 008, section 4), with
  # +AppRun+, a symbolic link to the app's program, which the runtime
  # runs; the 256-pixel icon at the top, named as the desktop entry's
  # +Icon+ names it; and <tt>.DirIcon</tt>, a link to it. It streams the
  # files into a SquashFS (Fledge::Squashfs) as they arrive, then writes
  # the runtime the Linux runtime carries (<tt>installer/appimage-runtime</tt>,
  # Fledge's build of AppImage's type 2 runtime) and the file system
  # after it, executable.
  #
  # Use it through Fledge::Assembly.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   image = Fledge::AppImage.new(identity:, to: "dist/My App-x86_64-linux.AppImage")
  #   image.add(Fledge::Entry.file("My App", launcher, mode: 0o755))
  #   image.finish({ "appimage-runtime" => runtime }) # => "dist/My App-x86_64-linux.AppImage"
  #--
  # SPDX-SnippetEnd
  #++
  class AppImage
    # The runtime's path among the runtime's installer files.
    RUNTIME = "appimage-runtime"

    # The size of the icon at the AppImage's top, as appimagetool
    # recommends it.
    ICON_SIZE = 256

    # Creates the AppImage of the app whose Fledge::Identity is +identity+,
    # written to +to+.
    #
    # [mtime] When everything in it was made, as Unix time.
    def initialize(identity:, to:, mtime: Time.now.to_i)
      @identity = identity
      @to = to
      @image = Tempfile.new(["fledge", ".squashfs"], binmode: true)
      @squashfs = Squashfs.new(@image, mtime:)
    end

    # Adds +entry+, whose path is relative to the built app's folder.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   image.add(Fledge::Entry.directory("lib"))
    #--
    # SPDX-SnippetEnd
    #++
    def add(entry)
      @squashfs.add(entry)
    end

    # Adds +AppRun+ and the icon, writes the AppImage with the runtime
    # from +kit+, the runtime's installer files by path, and returns its
    # path. Raises Fledge::Error when the runtime has no AppImage runtime.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   image.finish({ "appimage-runtime" => runtime }) # => "dist/My App-x86_64-linux.AppImage"
    #--
    # SPDX-SnippetEnd
    #++
    def finish(kit)
      runtime = kit[RUNTIME] or raise Error, "the runtime has no installer/#{RUNTIME}, which runtimes carry from Fledge 0.0.1.pre.7 on"
      appdir.each { |entry| @squashfs.add(entry) }
      @squashfs.finish
      @image.rewind
      File.open(@to, "wb") do |out|
        out.write(runtime.content)
        IO.copy_stream(@image, out)
      end
      File.chmod(0o755, @to)
      @to
    ensure
      @image.close!
    end

    # Removes what the AppImage has written, after a build that failed.
    def abort
      @image.close!
      FileUtils.rm_f(@to)
    end

    # What an AppDir has besides the app's folder: +AppRun+, and the icon
    # and <tt>.DirIcon</tt> when the app has an icon.
    private def appdir
      entries = [Entry.symlink("AppRun", @identity.name)]
      icon = @identity.icon
      return entries unless icon

      name = "#{@identity.identifier}.png"
      entries << Entry.file(name, icon.png(ICON_SIZE))
      entries << Entry.symlink(".DirIcon", name)
    end
  end
end
