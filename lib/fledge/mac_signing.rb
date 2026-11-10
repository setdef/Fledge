# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "command"
require_relative "notary"

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
  # proves the rest on any Mac. When Apple's timestamp server does not
  # answer, codesign is run again after a wait, a few times, and any
  # other failure, such as an identity the keychain lacks, fails at once
  # (doc/contributors/design/signing.md, "Timestamps").
  #
  # A signer given a Fledge::Notary (<tt>fledge build --notarize</tt>)
  # carries it to the build, which has Apple notarize what was signed
  # (ADR 033).
  #
  # Use it through Fledge::Signing, which <tt>fledge build --sign</tt> calls.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    # and libraries the app did not sign (ADR 050).
    ENTITLEMENTS = File.join(File.dirname(__FILE__), "templates", "macos", "entitlements.plist")

    # Where codesign comes from.
    INSTALL = "It comes with macOS, in /usr/bin."

    # What codesign prints when Apple's timestamp server did not answer
    # or sent no timestamp: the Security framework's descriptions of
    # errSecTimestampServiceNotAvailable and errSecTimestampMissing
    # (<Security/SecBase.h>), the two VS Code signs again for.
    TIMESTAMP_FAILURES = ["The timestamp service is not available.", "A timestamp was expected but was not found."].freeze

    # The seconds to wait before each run of codesign after the first
    # while it fails with one of TIMESTAMP_FAILURES, as Defold waits:
    # five runs in all.
    WAITS = [5, 10, 20, 40].freeze

    # The identity codesign signs with: a name or SHA-1 hash in the
    # keychain, or "-" for an ad hoc signature.
    attr_reader :identity

    # The Fledge::Notary that notarizes what this signs, or +nil+ when the
    # build does not notarize.
    attr_reader :notary

    # Creates the signer for +identity+, which runs codesign again after
    # each of +waits+, in seconds, while Apple's timestamp server does
    # not answer, and whose build +notary+ notarizes, when given one.
    def initialize(identity, waits: WAITS, notary: nil)
      @identity = identity
      @waits = waits
      @notary = notary
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
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MacSigning.new("-").sign_folder("dist/Hello-arm64-darwin")
    #--
    # SPDX-SnippetEnd
    #++
    def sign_folder(folder)
      files = Signing.code_files(folder, :macho).reject { |path| MacSigning.object_file?(path) }
      files.each_slice(100) { |slice| codesign(*code_options, *slice) }
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
      codesign(*code_options, *helpers) unless helpers.empty?
      codesign(*code_options, "--identifier", identifier, path)
    end

    # Signs the disk image at +path+, after the bundle in it, as
    # notarization asks of an image it staples a ticket to.
    def sign_image(path)
      codesign("--force", "--sign", @identity, *timestamp, path)
    end

    # Runs codesign with +arguments+, and again after each of the waits
    # while it fails with one of TIMESTAMP_FAILURES. Signing again is
    # safe: every run has --force, which replaces a signature already
    # made.
    private def codesign(*)
      waits = @waits
      begin
        Command.run("codesign", *, install: INSTALL)
      rescue Error => e
        wait, *waits = waits
        raise unless wait && TIMESTAMP_FAILURES.any? { |failure| e.message.include?(failure) }

        sleep(wait)
        retry
      end
    end

    # codesign's request for a secure timestamp from Apple's server, but
    # for an ad hoc signature, which has no certificate to stamp.
    private def timestamp
      (@identity == "-") ? %w[] : %w[--timestamp]
    end
  end
end
