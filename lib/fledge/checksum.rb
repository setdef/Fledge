# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "digest"

module Fledge
  # Writes the SHA-256 checksum file beside a file <tt>fledge build</tt>
  # wrote.
  #
  # Every package manager that installs a console app from a release
  # (a Scoop manifest, a Homebrew formula, a winget manifest, an AUR
  # +PKGBUILD+) names the archive by its address and its SHA-256, so a
  # developer who publishes one needs that hash for each archive.
  # Each platform's app is built on its own computer (ADR 010), so one
  # list for a whole release, as GoReleaser's <tt>checksums.txt</tt>, would be
  # written once per computer under one name; a file per archive, as
  # cargo-dist writes and GoReleaser writes with +split+, never collides.
  #
  # This module writes <tt>FILE.sha256</tt> beside +FILE+, one line in the
  # format of GNU coreutils' +sha256sum+: the hash in lowercase hex, two
  # spaces, and the file's name without its folder, so that
  # <tt>sha256sum -c</tt> (or <tt>shasum -a 256 -c</tt> on macOS) checks it
  # from the folder both are in (ADR 029, section 4).
  #
  # Use it on each file the build prints.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Checksum.write("dist/Hello-x86_64-linux.tar.gz") # => "dist/Hello-x86_64-linux.tar.gz.sha256"
  #   File.read("dist/Hello-x86_64-linux.tar.gz.sha256")       # => "5f1c...e2  Hello-x86_64-linux.tar.gz\n"
  #--
  # SPDX-SnippetEnd
  #++
  module Checksum
    # The extension of a checksum file.
    EXTENSION = ".sha256"

    # Writes +path+'s checksum file beside it, replacing any, and returns
    # its path.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Checksum.write("dist/Hello-x64-mingw-ucrt.zip") # => "dist/Hello-x64-mingw-ucrt.zip.sha256"
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(path)
      checksum = "#{path}#{EXTENSION}"
      File.binwrite(checksum, "#{Digest::SHA256.file(path).hexdigest}  #{File.basename(path)}\n")
      checksum
    end
  end
end
