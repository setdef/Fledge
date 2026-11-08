# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tmpdir"
require_relative "command"
require_relative "mac_bundle"

module Fledge
  # A macOS app's disk image: the <tt>.dmg</tt> a person downloads,
  # opens, and drags the app out of into Applications.
  #
  # A Mac app is downloaded as a disk image more than any other way, and
  # notarization staples its ticket to a disk image as it cannot to a
  # <tt>.zip</tt> (Plan 002, "Signing and notarization"). Tauri's bundler
  # makes one with create-dmg, which runs +hdiutil+, and so do
  # electron-builder and Briefcase; every Mac has it.
  #
  # This class holds what Tauri's images hold: the app's bundle,
  # <tt>NAME.app</tt>, and a symbolic link named +Applications+ to
  # <tt>/Applications</tt>, which create-dmg adds so a person can drag
  # the app onto it; the volume is named after the app. It copies the
  # bundle with +ditto+, which keeps its signature, links, and modes, into
  # a folder beside the link, and has <tt>hdiutil create</tt> make a
  # read-only, zlib-compressed image of it (UDZO) on a Mac OS Extended
  # volume, as create-dmg makes one (ADR 010).
  #
  # <tt>hdiutil create</tt> makes the image from a scratch volume it
  # mounts and detaches, and fails with "Resource busy" when another
  # process still holds that volume, as XProtect does now and then on a
  # GitHub macOS runner. create-dmg runs it again after 2, 4, 8, and 16
  # seconds when its output says so, and this class does the same; any
  # other failure fails the build at once.
  #
  # Use it through Fledge::Installers.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Dmg.write("dist/My App-arm64-darwin/My App.app", name: "My App", to: "dist/My App-arm64-darwin.dmg")
  #   # => "dist/My App-arm64-darwin.dmg"
  #--
  # SPDX-SnippetEnd
  #++
  module Dmg
    # The link to the Applications folder, as create-dmg names it.
    APPLICATIONS = "Applications"

    # What hdiutil says when another process holds its volume, which
    # create-dmg looks for before it tries again.
    BUSY = "Resource busy"

    # The seconds to wait before each try after the first, as
    # create-dmg waits: five tries in all.
    WAITS = [2, 4, 8, 16].freeze

    # Writes the disk image of the bundle at +bundle+ to +to+, its volume
    # named +name+, signs it with +signing+ (Fledge::MacSigning#sign_image)
    # when given one, and returns +to+. Tries hdiutil again after each of
    # +waits+, in seconds, while it finds its volume busy. Raises
    # Fledge::Error when ditto, hdiutil, or codesign fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Dmg.write(bundle, name: "My App", to: "dist/My App-arm64-darwin.dmg")
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(bundle, name:, to:, signing: nil, waits: WAITS)
      Dir.mktmpdir("fledge-dmg") do |stage|
        Command.run("ditto", bundle, File.join(stage, File.basename(bundle)), install: MacBundle::INSTALL)
        File.symlink("/Applications", File.join(stage, APPLICATIONS))
        FileUtils.rm_f(to)
        create(stage, name:, to:, waits:)
      end
      signing&.sign_image(to)
      to
    end

    # Runs <tt>hdiutil create</tt> on the folder +stage+, and again after
    # each of +waits+ while it fails with BUSY.
    def self.create(stage, name:, to:, waits:)
      Command.run("hdiutil", "create", "-volname", name, "-srcfolder", stage, "-fs", "HFS+", "-format", "UDZO", "-ov", to,
        install: MacBundle::INSTALL)
    rescue Error => e
      wait, *waits = waits
      raise unless wait && e.message.include?(BUSY)

      sleep(wait)
      retry
    end
    private_class_method :create
  end
end
