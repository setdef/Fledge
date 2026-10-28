# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "command"

module Fledge
  # Packs a folder into the archive it ships in, and unpacks one, with
  # the computer's own tar.
  #
  # A runtime arrives as a <tt>.tar.gz</tt>, and a built app leaves as
  # one, or as a <tt>.zip</tt> on Windows, where a person opens one with
  # a double-click. Every computer that builds an app has a tar that
  # reads and writes both without losing an executable bit or a symbolic
  # link: GNU tar on Linux, bsdtar (libarchive) on macOS, and on Windows
  # 10 and 11 the bsdtar Windows ships as <tt>System32\\tar.exe</tt>,
  # which writes ZIP too. Fledge wrote its own tar and ZIP formats only
  # so that one computer could build every platform (ADR 010).
  #
  # This module runs that tar. It packs a folder under its own name, so
  # the archive unpacks into one folder; it unpacks an archive into a
  # folder; and it lists an archive's paths and reads one file from it,
  # which is how Fledge reads what a runtime holds before it unpacks it.
  # On macOS it asks bsdtar for no AppleDouble files (+COPYFILE_DISABLE+),
  # which no other computer reads. On Windows it names
  # <tt>System32\\tar.exe</tt> itself, since another tar on the +PATH+,
  # such as Git's GNU tar, writes no ZIP.
  #
  # Use it to unpack a runtime and to pack a built app.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Archive.pack("dist/MyApp-x86_64-linux", to: "dist/MyApp-x86_64-linux.tar.gz")
  #   Fledge::Archive.unpack("dist/MyApp-x86_64-linux.tar.gz", into: "/tmp/unpacked")
  #   Fledge::Archive.names("dist/MyApp-x86_64-linux.tar.gz").first # => "MyApp-x86_64-linux/"
  #--
  # SPDX-SnippetEnd
  #++
  module Archive
    # The extension of a gzipped tar archive.
    TAR_GZ = ".tar.gz"

    # The extension of a ZIP archive.
    ZIP = ".zip"

    # What to do when this computer has no tar.
    INSTALL = "Every macOS, Linux, and Windows 10 or newer has one; install tar."

    # Packs +folder+ into the archive +to+, whose extension, TAR_GZ or
    # ZIP, says which, under +folder+'s own name, and returns +to+.
    # Raises Fledge::Error when tar fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.pack("dist/MyApp-x64-mingw-ucrt", to: "dist/MyApp-x64-mingw-ucrt.zip")
    #--
    # SPDX-SnippetEnd
    #++
    def self.pack(folder, to:)
      format = to.end_with?(ZIP) ? ["--format", "zip", "-cf"] : ["-czf"]
      FileUtils.rm_f(to)
      Command.run(tar, *format, to, "-C", File.dirname(folder), File.basename(folder), env: { "COPYFILE_DISABLE" => "1" }, install: INSTALL)
      to
    end

    # Unpacks the archive +archive+ into the folder +into+, which it
    # creates. Raises Fledge::Error when tar fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.unpack("fledge-runtime-0.0.1-x86_64-linux.tar.gz", into: "/tmp/runtime")
    #--
    # SPDX-SnippetEnd
    #++
    def self.unpack(archive, into:)
      FileUtils.mkdir_p(into)
      Command.run(tar, "-xf", archive, "-C", into, install: INSTALL)
      into
    end

    # The path of every entry in +archive+, as tar lists them, a folder's
    # with a slash at its end, one per line as tar prints them (with
    # Windows' line endings on Windows).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.names("hello.tar.gz") # => ["hello/", "hello/hello"]
    #--
    # SPDX-SnippetEnd
    #++
    def self.names(archive)
      Command.read(tar, "-tf", archive, install: INSTALL).force_encoding(Encoding::UTF_8).lines(chomp: true)
    end

    # The contents of the file +name+ in +archive+, as bytes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.read("hello.tar.gz", "hello/main.rb") # => "puts 'hi'\n"
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(archive, name)
      Command.read(tar, "-xOf", archive, name, install: INSTALL)
    end

    # The tar to run: Windows' own, or the first on the +PATH+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Archive.tar # => "tar", or "C:\\Windows\\System32\\tar.exe"
    #--
    # SPDX-SnippetEnd
    #++
    def self.tar
      return "tar" unless Gem.win_platform?

      File.join(ENV.fetch("SystemRoot", "C:\\Windows"), "System32", "tar.exe")
    end
  end
end
