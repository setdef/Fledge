# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tmpdir"
require_relative "command"
require_relative "error"

module Fledge
  # A Linux app as one file a person downloads and runs on any
  # distribution: an AppImage.
  #
  # A <tt>.tar.gz</tt> has to be unpacked, and a package for one family
  # of distributions misses the rest. An AppImage is a program (its
  # runtime) followed by a SquashFS file system that holds the app; run,
  # the runtime mounts the file system with FUSE and runs its +AppRun+,
  # and where there is no FUSE, <tt>APPIMAGE_EXTRACT_AND_RUN=1</tt> has it
  # extract the app and run that instead (ADR 009). Tauri's bundler and
  # Briefcase make one with appimagetool, which runs mksquashfs.
  #
  # This module makes one as appimagetool does (ADR 010): it copies the
  # built app's folder, which already has the desktop entry at its top
  # (ADR 008, section 4), into an AppDir, adds +AppRun+, a symbolic link
  # to the app's program, the 256-pixel icon at the top, named as the
  # desktop entry's +Icon+ names it, and <tt>.DirIcon</tt>, a link to it;
  # has squashfs-tools' +mksquashfs+ write the file system with
  # appimagetool's options (zstd, blocks of 128 KiB, root as every item's
  # owner) after room for the runtime; and writes the runtime, AppImage's
  # own released type 2 runtime, which the Linux runtime carries in
  # <tt>tools/appimage-runtime</tt>, into that room.
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

    # What to do when this computer has no mksquashfs.
    INSTALL = "Install squashfs-tools 4.4 or newer, such as with sudo apt install squashfs-tools or sudo dnf install squashfs-tools."

    # mksquashfs's options, appimagetool's: zstd, which AppImage's
    # runtime reads, in blocks of 128 KiB, every item owned by root,
    # replacing anything there, and dated 0.
    OPTIONS = %w[-comp zstd -b 128K -root-owned -noappend -mkfs-time 0 -quiet].freeze

    # Writes the AppImage of the app whose Fledge::Identity is +identity+
    # and whose built folder is +folder+ to +to+, with the runtime in
    # +tools+, the runtime's tools folder, and returns +to+. Raises
    # Fledge::Error when the runtime has no AppImage runtime or mksquashfs
    # fails.
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
      raise Error, "the runtime has no tools/#{RUNTIME}, which Linux runtimes carry from Fledge 0.0.1.pre.8 on" unless runtime && File.file?(runtime)

      Dir.mktmpdir("fledge-appimage") do |work|
        appdir = File.join(work, "AppDir")
        FileUtils.cp_r(folder, appdir, preserve: true)
        add_appdir(appdir, identity)
        Command.run("mksquashfs", appdir, to, "-offset", File.size(runtime).to_s, *OPTIONS, install: INSTALL)
      end
      File.open(to, "r+b") { |image| image.write(File.binread(runtime)) }
      File.chmod(0o755, to)
      to
    end

    # Adds what an AppDir has besides the app's folder: +AppRun+, and the
    # icon and <tt>.DirIcon</tt> when the app has an icon.
    private_class_method def self.add_appdir(appdir, identity)
      File.symlink(identity.name, File.join(appdir, "AppRun"))
      icon = identity.icon
      return unless icon

      name = "#{identity.identifier}.png"
      FileUtils.cp(icon.png(ICON_SIZE), File.join(appdir, name))
      File.symlink(name, File.join(appdir, ".DirIcon"))
    end
  end
end
