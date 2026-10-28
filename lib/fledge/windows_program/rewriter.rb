# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class WindowsProgram
    # Writes a copy of a program with a new resource section in place of
    # its old one: the sections after it move up to make room, and the
    # headers that describe them, the data directories inside them, the
    # image's sizes, and its checksum follow.
    class Rewriter # :nodoc:
      # A rewriter of the program in +bytes+, whose +headers+ are read.
      def initialize(bytes, headers)
        @bytes = bytes
        @headers = headers
      end

      # The program with +table+ as the raw data of +section+, and the
      # sections in +later+ moved to follow it.
      def rewrite(section, table, later)
        raw_size = align(table.bytesize, @headers.u32(@headers.field(:file_alignment)))
        out = @bytes.byteslice(0, section.raw).to_s + table.ljust(raw_size, "\0")
        write_section(out, section, size: table.bytesize, address: section.address, raw_size:, raw: section.raw)
        write_directory(out, RESOURCE_DIRECTORY, section.address, table.bytesize)
        image_size = append_moved(out, later, section.address + table.bytesize)
        finish_headers(out, image_size, raw_size - section.raw_size)
        out
      end

      # Appends the sections in +later+ to +out+, in file order, each at the
      # next aligned virtual address after +address+, and returns the end of
      # the last, aligned: the image's new size.
      private def append_moved(out, later, address)
        alignment = @headers.u32(@headers.field(:section_alignment))
        address = align(address, alignment)
        later.sort_by(&:raw).each do |moved|
          raw = out.bytesize
          out << @bytes.byteslice(moved.raw, moved.raw_size).to_s
          move_directories(out, moved, address)
          write_section(out, moved, size: moved.size, address:, raw_size: moved.raw_size, raw:)
          address = align(address + moved.size, alignment)
        end
        address
      end

      # Writes the image's new size, its initialized data grown by +growth+
      # bytes, and, when the program had one, its new checksum.
      private def finish_headers(out, image_size, growth)
        put32(out, @headers.field(:image_size), image_size)
        initialized_data = @headers.field(:initialized_data)
        put32(out, initialized_data, @headers.u32(initialized_data) + growth)
        checksum = @headers.field(:checksum)
        put32(out, checksum, WindowsProgram.checksum(out, checksum)) unless @headers.u32(checksum).zero?
      end

      # Points every data directory inside +moved+ at its new +address+.
      private def move_directories(out, moved, address)
        @headers.directory_count.times do |index|
          rva, size = @headers.directory(index)
          next unless rva >= moved.address && rva < moved.address + [moved.size, moved.raw_size].max

          write_directory(out, index, rva - moved.address + address, size)
        end
      end

      private def write_section(out, section, size:, address:, raw_size:, raw:)
        out.bytesplice(@headers.section_offset(section.index) + 8, 16, [size, address, raw_size, raw].pack("V4"))
      end

      private def write_directory(out, index, rva, size)
        out.bytesplice(@headers.directory_offset(index), 8, [rva, size].pack("V2"))
      end

      private def put32(out, at, value)
        out.bytesplice(at, 4, [value].pack("V"))
      end

      private def align(value, alignment)
        ((value + alignment - 1) / alignment) * alignment
      end
    end
  end
end
