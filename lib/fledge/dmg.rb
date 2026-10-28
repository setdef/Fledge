# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tempfile"
require_relative "entry"
require_relative "hfs_plus"
require_relative "udif"

module Fledge
  # A macOS app's disk image: the <tt>.dmg</tt> a person downloads,
  # opens, and drags the app out of into Applications.
  #
  # A Mac app is downloaded as a disk image more than any other way, and
  # notarization staples its ticket to a disk image as it cannot to a
  # <tt>.zip</tt> (Plan 002, "Signing and notarization"). Tauri's bundler
  # makes one with <tt>create-dmg</tt>, which runs +hdiutil+, so only on
  # a Mac; electron-builder and Briefcase also run hdiutil. Fledge builds
  # a Mac's app on any computer (ADR 001), so it writes the image itself
  # (ADR 009), as Mozilla's builds of Firefox for macOS write theirs on
  # Linux with libdmg-hfsplus.
  #
  # This class holds what Tauri's images hold: the app's bundle,
  # <tt>NAME.app</tt>, and a symbolic link named +Applications+ to
  # <tt>/Applications</tt>, which create-dmg adds so a person can drag
  # the app onto it; the volume is named after the app. It streams the
  # app's files into a Mac OS Extended volume (Fledge::HfsPlus) as they
  # arrive, then compresses that into the image (Fledge::Udif). The
  # bundle inside is the one the build signed ad hoc, byte for byte, so
  # <tt>codesign --verify --strict --deep</tt> accepts it in the mounted
  # image and wherever it is copied.
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
  #   dmg = Fledge::Dmg.new(name: "My App", to: "dist/My App-arm64-darwin.dmg")
  #   dmg.add(Fledge::Entry.file("My App.app/Contents/Info.plist", plist))
  #   dmg.finish # => "dist/My App-arm64-darwin.dmg"
  #--
  # SPDX-SnippetEnd
  #++
  class Dmg
    # The link to the Applications folder, as create-dmg names it.
    APPLICATIONS = Entry.symlink("Applications", "/Applications")

    # The type a partition holding Fledge::HfsPlus's volume has.
    PARTITION = "Apple_HFSX"

    # Creates the image of the app named +name+, written to +to+.
    #
    # [mtime] When everything in it was made, as Unix time.
    def initialize(name:, to:, mtime: Time.now.to_i)
      @to = to
      @volume_file = Tempfile.new(["fledge", ".hfs"], binmode: true)
      @volume = HfsPlus.new(@volume_file, name:, mtime:)
    end

    # Adds +entry+, whose path is relative to the built app's folder, to
    # the image.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   dmg.add(Fledge::Entry.directory("My App.app"))
    #--
    # SPDX-SnippetEnd
    #++
    def add(entry)
      @volume.add(entry)
    end

    # Adds the link to Applications, writes the image, and returns its
    # path. The runtime's installer files (+kit+) hold nothing an image
    # needs.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   dmg.finish # => "dist/My App-arm64-darwin.dmg"
    #--
    # SPDX-SnippetEnd
    #++
    def finish(_kit = {})
      @volume.add(APPLICATIONS)
      @volume.finish
      @volume_file.rewind
      Udif.write(@volume_file, to: @to, partition: PARTITION)
    ensure
      @volume_file.close!
    end

    # Removes what the image has written, after a build that failed.
    def abort
      @volume_file.close!
      FileUtils.rm_f(@to)
    end
  end
end
