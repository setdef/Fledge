# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "command"

module Fledge
  # Signs a macOS app with its developer's identity, through codesign.
  #
  # Every app Fledge builds for macOS already runs: Apple Silicon runs
  # only signed code, so the launcher arrives signed, and a windowed
  # app's bundle is signed ad hoc (ADR 008). But Gatekeeper trusts only a
  # Developer ID signature that Apple has notarized, and notarization
  # takes only code signed with the hardened runtime and a secure
  # timestamp, every Mach-O file of it, not just the program.
  #
  # This class signs with an identity from the developer's keychain, as
  # <tt>codesign --sign</tt> names one: every Mach-O file of a console
  # app's folder, or of a bundle's <tt>Contents/Resources</tt> and then the
  # bundle, with the hardened runtime, a timestamp from Apple's server,
  # and the entitlements Ruby needs (ENTITLEMENTS); and a disk image
  # after that. The ad hoc identity, "-", signs the same way but for the
  # timestamp, which needs a certificate to stamp: Gatekeeper trusts it
  # no more than the ad hoc signature Fledge gives every bundle, but it
  # proves the rest on any Mac.
  #
  # Use it through Fledge::Signing, which <tt>fledge build --sign</tt> calls.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   signing = Fledge::MacSigning.new("Developer ID Application: Example (ABCDE12345)")
  #   signing.sign_folder("dist/Hello-arm64-darwin")
  #   signing.sign_bundle("dist/Hello Window-arm64-darwin/Hello Window.app", identifier: "com.example.HelloWindow")
  #   signing.sign_image("dist/Hello Window-arm64-darwin.dmg")
  #--
  # SPDX-SnippetEnd
  #++
  class MacSigning
    # The entitlements every Mach-O file is signed with, Briefcase's
    # defaults: executable memory made without MAP_JIT, which YJIT makes,
    # and libraries the app did not sign (ADR 016).
    ENTITLEMENTS = File.join(File.dirname(__FILE__), "templates", "macos", "entitlements.plist")

    # Where codesign comes from.
    INSTALL = "It comes with macOS, in /usr/bin."

    # The identity codesign signs with: a name or SHA-1 hash in the
    # keychain, or "-" for an ad hoc signature.
    attr_reader :identity

    # Creates the signer for +identity+.
    def initialize(identity)
      @identity = identity
    end

    # codesign's options for every piece of code: replace any signature,
    # sign with the identity, the hardened runtime, a secure timestamp
    # from Apple's server (but for an ad hoc signature), and ENTITLEMENTS.
    def code_options
      ["--force", "--sign", @identity, "--options", "runtime", *timestamp, "--entitlements", ENTITLEMENTS]
    end

    # Signs every Mach-O program and library under +folder+
    # (Fledge::Signing.code_files), a console app's folder or a bundle's
    # resources, leaving out object files, which a gem's build can leave
    # beside its extension and which no one runs or loads.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MacSigning.new("-").sign_folder("dist/Hello-arm64-darwin")
    #--
    # SPDX-SnippetEnd
    #++
    def sign_folder(folder)
      files = Signing.code_files(folder, :macho).reject { |path| MacSigning.object_file?(path) }
      files.each_slice(100) { |slice| Command.run("codesign", *code_options, *slice, install: INSTALL) }
    end

    # Whether the Mach-O file at +path+ is an object file (MH_OBJECT, 1,
    # the file type a thin Mach-O header holds at byte 12, in
    # <mach-o/loader.h>), which codesign cannot sign.
    def self.object_file?(path)
      header = File.binread(path, 16).to_s
      header.bytesize == 16 && header.unpack1("N") != 0xCAFEBABE && header.byteslice(12, 4).to_s.unpack1("V") == 1
    end

    # Signs the bundle at +path+ in place of the ad hoc signature Fledge
    # gives every bundle: its resources' Mach-O files and its +helpers+
    # (the console programs in <tt>Contents/MacOS</tt> beside its own
    # program, ADR 024) first, inside out as Apple asks of nested code,
    # then the bundle itself, as +identifier+, which seals them.
    def sign_bundle(path, identifier:, helpers: [])
      sign_folder(File.join(path, "Contents", "Resources"))
      Command.run("codesign", *code_options, *helpers, install: INSTALL) unless helpers.empty?
      Command.run("codesign", *code_options, "--identifier", identifier, path, install: INSTALL)
    end

    # Signs the disk image at +path+, after the bundle in it, as
    # notarization asks of an image it staples a ticket to.
    def sign_image(path)
      Command.run("codesign", "--force", "--sign", @identity, *timestamp, path, install: INSTALL)
    end

    # codesign's request for a secure timestamp from Apple's server, but
    # for an ad hoc signature, which has no certificate to stamp.
    private def timestamp
      (@identity == "-") ? %w[] : %w[--timestamp]
    end
  end
end
