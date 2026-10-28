# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../entry"
require_relative "../error"

module Fledge
  module TarGz
    # Adds entries to an open archive. Fledge::TarGz.write makes one.
    #
    # A tar header has a hundred bytes for a name and a hundred and
    # fifty-five for the folders before it, and Ruby's standard library
    # holds paths longer than that. The writer splits a path across the
    # two fields when it can and writes a pax record otherwise, so any
    # path fits.
    #
    # Use it through Fledge::TarGz.write.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::TarGz.write("a.tar.gz") { |archive| archive.add(Fledge::Entry.directory("a")) }
    #--
    # SPDX-SnippetEnd
    #++
    class Writer
      # Creates a writer.
      #
      # [io] Where the tar stream goes, such as a Zlib::GzipWriter.
      # [mtime] The modification time of every entry, in seconds.
      def initialize(io, mtime:)
        @io = io
        @mtime = mtime
      end

      # Adds +entry+ to the archive.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   archive.add(Fledge::Entry.file("hello/main.rb", "puts 1\n"))
      #--
      # SPDX-SnippetEnd
      #++
      def add(entry)
        name = (entry.type == :directory) ? "#{entry.path}/" : entry.path
        size = (entry.type == :file) ? entry.content.bytesize : 0
        write_pax(name, entry.link)
        @io.write(header(name, entry, size))
        write_padded(entry.content) if entry.type == :file
      end

      # Ends the archive with the two empty blocks tar expects.
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
        @io.write("\0" * (BLOCK * 2))
      end

      private def write_pax(name, link)
        records = +""
        records << pax_record("path", name) unless split_name(name)
        records << pax_record("linkpath", link) if link.bytesize > 100
        return if records.empty?

        @io.write(raw_header("PaxHeader", 0o644, records.bytesize, "x", "", ""))
        write_padded(records)
      end

      private def pax_record(key, value)
        body = " #{key}=#{value}\n".b
        length = body.bytesize + 1
        length += 1 while "#{length}#{body}".bytesize > length
        "#{length}#{body}".b
      end

      private def header(name, entry, size)
        prefix, base = split_name(name) || ["", name.b.byteslice(0, 100) || ""]
        typeflag = { file: "0", directory: "5", symlink: "2" }.fetch(entry.type)
        link = entry.link.b.byteslice(0, 100) || ""
        raw_header(base, entry.mode, size, typeflag, link, prefix)
      end

      # [prefix, name] for a path that fits ustar's fields, or nil.
      private def split_name(name)
        bytes = name.b
        return ["", bytes] if bytes.bytesize <= 100

        index = bytes.byteslice(0, 156)&.rindex("/")
        while index
          prefix = bytes.byteslice(0, index) || ""
          rest = bytes.byteslice(index + 1, bytes.bytesize) || ""
          return [prefix, rest] if prefix.bytesize <= 155 && rest.bytesize <= 100 && !rest.empty?

          index = index.zero? ? nil : prefix.rindex("/")
        end
        nil
      end

      private def raw_header(name, mode, size, typeflag, link, prefix)
        fields = [
          name,
          format("%07o", mode & 0o7777),
          "0000000",
          "0000000",
          format("%011o", size),
          format("%011o", @mtime),
          " " * 8,
          typeflag,
          link,
          "ustar",
          "00",
          "",
          "",
          "0000000",
          "0000000",
          prefix,
        ]
        block = fields.pack("a100a8a8a8a12a12a8a1a100a6a2a32a32a8a8a155").ljust(BLOCK, "\0")
        checksum = block.bytes.sum
        block[148, 8] = format("%06o\0 ", checksum)
        block
      end

      private def write_padded(bytes)
        @io.write(bytes)
        remainder = bytes.bytesize % BLOCK
        @io.write("\0" * (BLOCK - remainder)) unless remainder.zero?
      end
    end
  end
end
