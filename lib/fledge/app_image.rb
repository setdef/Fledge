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
  # This module lays the AppImage's file system out as AppImage's
  # specification lays out an AppDir: the built app's folder, which
  # already has the desktop entry at its top (ADR 008, section 4), with
  # +AppRun+, a symbolic link to the app's program, which the runtime
  # runs; the 256-pixel icon at the top, named as the desktop entry's
  # +Icon+ names it; and <tt>.DirIcon</tt>, a link to it. It writes the
  # files into a SquashFS (Fledge::Squashfs), then writes
  # the runtime the Linux runtime carries (<tt>tools/appimage-runtime</tt>,
  # Fledge's build of AppImage's type 2 runtime) and the file system
  # after it, executable.
  #
  # Use it through Fledge::Installers.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::AppImage.write(identity:, folder: "dist/My App-x86_64-linux", tools:, to: "dist/My App-x86_64-linux.AppImage")
  #   # => "dist/My App-x86_64-linux.AppImage"
  #--
  # SPDX-SnippetEnd
  #++
  module AppImage
    # The AppImage runtime's path in the runtime's tools folder.
    RUNTIME = "appimage-runtime"

    # The size of the icon at the AppImage's top, as appimagetool
    # recommends it.
    ICON_SIZE = 256

    # Writes the AppImage of the app whose Fledge::Identity is +identity+
    # and whose built folder is +folder+ to +to+, with the runtime in
    # +tools+, the runtime's tools folder, and returns +to+. Raises
    # Fledge::Error when the runtime has no AppImage runtime.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::AppImage.write(identity:, folder: "dist/My App-x86_64-linux", tools:, to: "dist/My App-x86_64-linux.AppImage")
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(identity:, folder:, tools:, to:)
      runtime = tools && File.join(tools, RUNTIME)
      unless runtime && File.file?(runtime)
        raise Error, "the runtime has no tools/#{RUNTIME}, which Linux runtimes carry from Fledge 0.0.1.pre.8 on"
      end

      Tempfile.create(["fledge", ".squashfs"], binmode: true) do |image|
        squashfs = Squashfs.new(image, mtime: Time.now.to_i)
        [*Entry.walk(folder), *appdir(identity)].each { |entry| squashfs.add(entry) }
        squashfs.finish
        image.rewind
        File.open(to, "wb") do |out|
          out.write(File.binread(runtime))
          IO.copy_stream(image, out)
        end
      end
      File.chmod(0o755, to)
      to
    end

    # What an AppDir has besides the app's folder: +AppRun+, and the icon
    # and <tt>.DirIcon</tt> when the app has an icon.
    private_class_method def self.appdir(identity)
      entries = [Entry.symlink("AppRun", identity.name)]
      icon = identity.icon
      return entries unless icon

      name = "#{identity.identifier}.png"
      entries << Entry.file(name, File.binread(icon.png(ICON_SIZE)))
      entries << Entry.symlink(".DirIcon", name)
    end
  end
end
