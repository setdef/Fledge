# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tmpdir"
require_relative "command"

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
  # Use it through Fledge::Installers.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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

    # Writes the disk image of the bundle at +bundle+ to +to+, its volume
    # named +name+, and returns +to+. Raises Fledge::Error when ditto or
    # hdiutil fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Dmg.write(bundle, name: "My App", to: "dist/My App-arm64-darwin.dmg")
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(bundle, name:, to:)
      Dir.mktmpdir("fledge-dmg") do |stage|
        Command.run("ditto", bundle, File.join(stage, File.basename(bundle)), install: "It comes with macOS.")
        File.symlink("/Applications", File.join(stage, APPLICATIONS))
        FileUtils.rm_f(to)
        Command.run("hdiutil", "create", "-volname", name, "-srcfolder", stage, "-fs", "HFS+", "-format", "UDZO", "-ov", to,
          install: "It comes with macOS.")
      end
      to
    end
  end
end
