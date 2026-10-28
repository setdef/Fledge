# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../entry"
require_relative "../error"

module Fledge
  module TarGz
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
