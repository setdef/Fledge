# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "binary"
require_relative "error"
require_relative "mac_signing"
require_relative "windows_signing"

module Fledge
  # Chooses how an app is signed with its developer's own credentials.
  #
  # macOS's Gatekeeper and Windows' SmartScreen warn about, or refuse, an
  # app downloaded from the internet that no one they trust has signed.
  # A developer who has done Apple's or Microsoft's ceremony has an
  # identity to sign with; one who has not still ships an app that works,
  # unsigned (decision 17). Signing has to come after Fledge has written
  # everything into the app, since a signature seals what it covers, and
  # before the archive and installers, which carry the signed files.
  #
  # This module turns the identity <tt>fledge build --sign</tt> names into
  # the signer for the system the build is for: Fledge::MacSigning, with
  # Apple's codesign, or Fledge::WindowsSigning, with Microsoft's signtool
  # (ADR 016). Each signs every compiled file of its system's own format,
  # which Signing.code_files finds.
  #
  # Use it to get the signer Fledge::Assembly hands each step that signs.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Signing.for(Fledge::Platform.local, nil)
  #   # => nil, an unsigned build
  #
  #   Fledge::Signing.for(Fledge::Platform.find("arm64-darwin"), "Developer ID Application: Example (ABCDE12345)")
  #   # => a Fledge::MacSigning
  #--
  # SPDX-SnippetEnd
  #++
  module Signing
    # The signer for +platform+ with +identity+, or +nil+ when there is no
    # identity. Raises Fledge::Error for a platform Fledge does not sign
    # for, or an identity its signer cannot take.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Signing.for(Fledge::Platform.find("x64-mingw-ucrt"), "0123456789ABCDEF0123456789ABCDEF01234567")
    #   # => a Fledge::WindowsSigning
    #--
    # SPDX-SnippetEnd
    #++
    def self.for(platform, identity, env: ENV)
      return nil if identity.nil?

      case platform.os
      when "darwin" then MacSigning.new(identity)
      when "windows" then WindowsSigning.new(identity, env:)
      else
        raise Error, "--sign signs apps for macOS and Windows; a Linux app carries no signature for its system to check, " \
          "so build it without --sign"
      end
    end

    # The paths of the files under +folder+ whose first bytes say they
    # are compiled code of +format+ (Fledge::Binary.format_of), sorted,
    # leaving out symbolic links, whose targets are signed where they are.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Signing.code_files("dist/Hello-arm64-darwin", :macho)
    #   # => ["dist/Hello-arm64-darwin/Hello", "dist/Hello-arm64-darwin/bin/ruby", ...]
    #--
    # SPDX-SnippetEnd
    #++
    def self.code_files(folder, format)
      Dir.glob("**/*", File::FNM_DOTMATCH, base: folder).sort.filter_map do |path|
        full = File.join(folder, path)
        next if File.symlink?(full) || !File.file?(full)

        full if Binary.format_of(File.binread(full, 4).to_s) == format
      end
    end
  end
end
