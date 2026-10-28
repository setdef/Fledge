# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"
require_relative "entry"
require_relative "error"
require_relative "zip/writer"

module Fledge
  # Writes .zip archives, the kind a Windows app ships in.
  #
  # A person on Windows opens a .zip by double-clicking it: Explorer
  # reads one with nothing installed, and a .tar.gz it does not offer to
  # open. Ruby's standard library writes gzip and, through Fledge::TarGz,
  # tar, but no zip, and a gem for it would be the only dependency
  # Fledge has.
  #
  # This module writes Fledge::Entry values into a zip as PKWARE's
  # APPNOTE.TXT describes it, the same way Fledge::TarGz writes a tar:
  # each file deflated with Zlib (or stored, when deflating would not make
  # it smaller), with its CRC-32 and sizes in its local header, so no
  # data descriptors are needed, and every name flagged as UTF-8, so
  # Windows reads a name like <tt>héllo wörld.exe</tt> as it was written.
  # Entries are marked as made on Unix, with their permission bits, as
  # Info-ZIP marks them, so unzip on macOS or Linux keeps an executable
  # bit; folders also carry MS-DOS's directory attribute.
  #
  # Its limits are those of a zip without the Zip64 extension, which
  # Fledge's apps are far from: at most MAX_ENTRIES files and folders, and
  # no file, and no archive, of 4 GiB or more. Past them it raises
  # Fledge::Error rather than write an archive some readers would
  # misread. It holds no symbolic links, which Windows would unpack as
  # small text files, so it refuses those too. It does not read zips:
  # runtimes arrive as .tar.gz on every platform.
  #
  # Use it to write a Windows app's archive.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Zip.write("hello.zip") do |archive|
  #     archive.add(Fledge::Entry.directory("hello"))
  #     archive.add(Fledge::Entry.file("hello/hello.exe", launcher, mode: 0o755))
  #   end
  #--
  # SPDX-SnippetEnd
  #++
  module Zip
    # The extension of a zip archive.
    EXTENSION = ".zip"

    # The most files and folders a zip without Zip64 holds: its count
    # fields are 16 bits wide, and their largest value means "see Zip64".
    MAX_ENTRIES = 0xFFFE

    # The largest size or offset a zip without Zip64 records: its fields
    # are 32 bits wide, and their largest value means "see Zip64".
    MAX_SIZE = 0xFFFFFFFE

    # The extension of the archives this module writes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Zip.extension # => ".zip"
    #--
    # SPDX-SnippetEnd
    #++
    def self.extension
      EXTENSION
    end

    # Writes the archive at +path+, yielding a Writer to add entries to,
    # and returns +path+. Stamps every entry with +mtime+ (default: the
    # current time), as seconds since 1970. Raises Fledge::Error for an
    # entry or an archive a zip without Zip64 cannot hold.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Zip.write("notes.zip") { |archive| archive.add(Fledge::Entry.file("a.txt", "a\n")) }
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(path, mtime: Time.now.to_i)
      File.open(path, "wb") do |file|
        writer = Writer.new(file, mtime:)
        yield writer
        writer.finish
      end
      path
    end
  end
end
