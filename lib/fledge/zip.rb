# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"
require_relative "entry"
require_relative "error"

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

    # Adds entries to an open archive. Fledge::Zip.write makes one.
    #
    # A zip ends with a central directory that repeats each entry's
    # header and says where it starts, and readers such as Windows' own
    # start there. The writer writes each entry as it is added, keeps its
    # central header, and writes them all when the archive is finished.
    #
    # Use it through Fledge::Zip.write.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Zip.write("a.zip") { |archive| archive.add(Fledge::Entry.directory("a")) }
    #--
    # SPDX-SnippetEnd
    #++
    class Writer
      # The version of the format a reader needs: 2.0, which added
      # deflate and folders.
      VERSION_NEEDED = 20

      # Who made the archive: Unix (3, the high byte), with version 3.0 of
      # the format, as Info-ZIP writes it, so the high half of each
      # entry's external attributes is a Unix mode.
      VERSION_MADE_BY = (3 << 8) | 30

      # General purpose flag bit 11: the entry's name is UTF-8.
      UTF8 = 0x0800

      # The compression method for data kept as it is.
      STORED = 0

      # The compression method for data compressed with deflate.
      DEFLATED = 8

      # MS-DOS's directory attribute, in the low byte of a folder's
      # external attributes.
      DOS_DIRECTORY = 0x10

      # The Unix file type of a regular file, above a mode's permission
      # bits.
      UNIX_FILE = 0o100000

      # The Unix file type of a folder, above a mode's permission bits.
      UNIX_DIRECTORY = 0o040000

      # Creates a writer.
      #
      # [io] Where the archive goes, such as a File opened for writing.
      # [mtime] The modification time of every entry, in seconds.
      def initialize(io, mtime:)
        @io = io
        @offset = 0
        @central = [] # : Array[String]
        @time, @date = dos_time(mtime)
      end

      # Adds +entry+ to the archive. Raises Fledge::Error for a symbolic
      # link, and for an entry that would take the archive past what a
      # zip without Zip64 holds.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   archive.add(Fledge::Entry.file("hello/app/main.rb", "puts 1\n"))
      #--
      # SPDX-SnippetEnd
      #++
      def add(entry)
        if entry.type == :symlink
          raise Error, "#{entry.path} is a symbolic link, which a .zip for Windows cannot hold. " \
            "Replace it with what it points to."
        end
        raise Error, "a .zip without Zip64 holds at most #{MAX_ENTRIES} files and folders" if @central.size >= MAX_ENTRIES

        name = ((entry.type == :directory) ? "#{entry.path}/" : entry.path).b
        method, data = compress(entry.content.b)
        record = [UTF8, method, @time, @date, Zlib.crc32(entry.content), data.bytesize, entry.content.bytesize]
        check_size(entry.path, [entry.content.bytesize, @offset])
        @central << central_header(name, record, external_attributes(entry), @offset)
        emit([0x04034b50, VERSION_NEEDED, *record, name.bytesize, 0].pack("VvvvvvVVVvv"), name, data)
      end

      # Writes the central directory and the end of central directory
      # record, which close the archive.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   writer.finish
      #--
      # SPDX-SnippetEnd
      #++
      def finish
        start = @offset
        emit(*@central)
        check_size("the archive", [@offset])
        count = @central.size
        emit([0x06054b50, 0, 0, count, count, @offset - start, start, 0].pack("VvvvvVVv"))
      end

      private def compress(content)
        return [STORED, content] if content.empty?

        deflate = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
        deflated = deflate.deflate(content, Zlib::FINISH)
        deflate.close
        (deflated.bytesize < content.bytesize) ? [DEFLATED, deflated] : [STORED, content]
      end

      private def external_attributes(entry)
        if entry.type == :directory
          ((UNIX_DIRECTORY | entry.mode) << 16) | DOS_DIRECTORY
        else
          (UNIX_FILE | entry.mode) << 16
        end
      end

      private def central_header(name, record, external, offset)
        fields = [0x02014b50, VERSION_MADE_BY, VERSION_NEEDED, *record, name.bytesize, 0, 0, 0, 0, external, offset]
        fields.pack("VvvvvvvVVVvvvvvVV") + name
      end

      private def check_size(what, sizes)
        return if sizes.all? { |size| size <= MAX_SIZE }

        raise Error, "#{what} is too large for a .zip without Zip64, which holds less than 4 GiB"
      end

      private def emit(*chunks)
        chunks.each do |chunk|
          @io.write(chunk)
          @offset += chunk.bytesize
        end
      end

      # [time, date] in MS-DOS's format, from +mtime+ in UTC. MS-DOS
      # counts years from 1980 in seven bits, so an earlier time becomes
      # the first moment of 1980 and a later one the last of 2107.
      private def dos_time(mtime)
        time = Time.at(mtime).utc
        return [0, (1 << 5) | 1] if time.year < 1980
        return [(23 << 11) | (59 << 5) | 29, (127 << 9) | (12 << 5) | 31] if time.year > 2107

        [(time.hour << 11) | (time.min << 5) | (time.sec / 2), ((time.year - 1980) << 9) | (time.month << 5) | time.day]
      end
    end
  end
end
