# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"
require_relative "entry"
require_relative "error"

module Fledge
  # Reads and writes gzipped tar archives, the kind a macOS or Linux app
  # ships in.
  #
  # A built app is useless if its launcher loses its executable bit or a
  # symlink turns into a copy on the way to the person who downloads it.
  # The tar command keeps both, but only from a disk that keeps them, and
  # a Windows disk does not, so an archive built from a folder on Windows
  # would ship a launcher nobody can run.
  #
  # This module writes Fledge::Entry values, which carry their own
  # permissions, straight into the archive, and reads them back the same
  # way, so the archive is right wherever it is built. It writes POSIX
  # ustar headers, with pax records for long paths, which every tar
  # reads; it reads the same, plus GNU long names.
  #
  # Use it to read a runtime and to write a built app.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::TarGz.write("hello.tar.gz") do |archive|
  #     archive.add(Fledge::Entry.directory("hello"))
  #     archive.add(Fledge::Entry.file("hello/hello", launcher, mode: 0o755))
  #   end
  #
  #   Fledge::TarGz.each_entry("hello.tar.gz") { |entry| puts entry.path }
  #   # hello
  #   # hello/hello
  #--
  # SPDX-SnippetEnd
  #++
  module TarGz
    # Tar's unit: headers and contents fill whole blocks of this size.
    BLOCK = 512

    # The extension of a gzipped tar archive.
    EXTENSION = ".tar.gz"

    # The extension of the archives this module writes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::TarGz.extension # => ".tar.gz"
    #--
    # SPDX-SnippetEnd
    #++
    def self.extension
      EXTENSION
    end

    # Writes the archive at +path+, yielding a Writer to add entries to,
    # and returns +path+. Stamps every entry with +mtime+ (default: the
    # current time), as seconds since 1970.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::TarGz.write("notes.tar.gz") { |archive| archive.add(Fledge::Entry.file("a.txt", "a\n")) }
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(path, mtime: Time.now.to_i)
      File.open(path, "wb") do |file|
        gzip = Zlib::GzipWriter.new(file, Zlib::BEST_COMPRESSION)
        gzip.mtime = Time.at(mtime)
        writer = Writer.new(gzip, mtime:)
        yield writer
        writer.finish
        gzip.finish
      end
      path
    end

    # Yields each Fledge::Entry in the archive at +path+, in order.
    # Raises Fledge::Error for an archive that is not a tar.gz, holds an
    # unsafe path, or holds a kind of entry an app has no use for (a hard
    # link or a device).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::TarGz.each_entry("hello.tar.gz") { |entry| puts entry.path if entry.type == :file }
    #--
    # SPDX-SnippetEnd
    #++
    def self.each_entry(path, &)
      File.open(path, "rb") do |file|
        Reader.new(Zlib::GzipReader.new(file)).each(&)
      end
    rescue Zlib::Error => e
      raise Error, "#{path} is not a .tar.gz archive (#{e.message})"
    end

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

    # Reads entries from a tar stream. Fledge::TarGz.each_entry makes
    # one.
    #
    # Archives come from outside Fledge: a runtime downloaded from a
    # release, or one a developer built. The reader checks each header's
    # checksum and makes each entry a Fledge::Entry, which refuses unsafe
    # paths, so a damaged or hostile archive stops the build instead of
    # writing outside the app.
    #
    # Use it through Fledge::TarGz.each_entry.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::TarGz.each_entry("runtime.tar.gz") { |entry| p entry.path }
    #--
    # SPDX-SnippetEnd
    #++
    class Reader
      # Creates a reader.
      #
      # [io] The tar stream, such as a Zlib::GzipReader.
      def initialize(io)
        @io = io
      end

      # Yields each entry in the stream, in order.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   reader.each { |entry| p entry.path }
      #--
      # SPDX-SnippetEnd
      #++
      def each
        overrides = {} # : Hash[String, String]
        while (block = read_block)
          typeflag = block.byteslice(156, 1) || ""
          size = number(block, 124, 12)
          data = read_padded(size)
          case typeflag
          when "x" then overrides.merge!(pax(data))
          when "L" then overrides["path"] = data.delete_suffix("\0").delete("\0")
          when "K" then overrides["linkpath"] = data.delete("\0")
          when "g" then next
          else
            yield entry(block, typeflag, data, overrides)
            overrides = {}
          end
        end
      end

      private def read_block
        block = @io.read(BLOCK)
        return nil if block.nil? || block.bytesize.zero?
        raise Error, "the archive ends in the middle of a header" if block.bytesize < BLOCK
        return nil if block.count("\0") == BLOCK

        verify_checksum(block)
        block
      end

      private def verify_checksum(block)
        expected = number(block, 148, 8)
        actual = (block.byteslice(0, 148) || "").bytes.sum + (32 * 8) + (block.byteslice(156, 356) || "").bytes.sum
        raise Error, "the archive is damaged: a header's checksum does not match" unless expected == actual
      end

      private def number(block, offset, length)
        field = (block.byteslice(offset, length) || "").delete("\0").strip
        raise Error, "the archive is damaged: #{field.inspect} is not an octal number" unless field.match?(/\A[0-7]*\z/)

        field.to_i(8)
      end

      private def read_padded(size)
        return "".b if size.zero?

        data = @io.read(size) || ""
        raise Error, "the archive ends in the middle of a file" if data.bytesize < size

        remainder = size % BLOCK
        @io.read(BLOCK - remainder) unless remainder.zero?
        data
      end

      private def pax(data)
        records = {} # : Hash[String, String]
        rest = data
        until rest.empty?
          length = rest[/\A\d+/].to_i
          raise Error, "the archive is damaged: a pax record has no length" if length.zero?

          record = rest.byteslice(0, length) || ""
          key, value = (record.split(" ", 2)[1] || "").chomp("\n").split("=", 2)
          records[key] = value.to_s if key
          rest = rest.byteslice(length, rest.bytesize) || ""
        end
        records
      end

      private def entry(block, typeflag, data, overrides)
        path = utf8(overrides.fetch("path") { ustar_name(block) }).delete_prefix("./").delete_suffix("/")
        mode = number(block, 100, 8) & 0o7777
        case typeflag
        when "0", "\0", "7" then Entry.file(path, data, mode:)
        when "5" then Entry.directory(path, mode:)
        when "2" then Entry.symlink(path, utf8(overrides.fetch("linkpath") { field(block, 157, 100) }))
        else raise Error, "#{path.inspect} is a kind of file an app cannot hold (tar type #{typeflag.inspect})"
        end
      end

      private def ustar_name(block)
        name = field(block, 0, 100)
        prefix = (block.byteslice(257, 5) == "ustar") ? field(block, 345, 155) : ""
        prefix.empty? ? name : "#{prefix}/#{name}"
      end

      private def field(block, offset, length)
        (block.byteslice(offset, length) || "").sub(/\0.*/m, "")
      end

      private def utf8(bytes)
        bytes.dup.force_encoding(Encoding::UTF_8)
      end
    end
  end
end
