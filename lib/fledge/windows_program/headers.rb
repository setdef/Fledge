# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"

module Fledge
  class WindowsProgram
    # A PE program's headers, as Microsoft's "PE Format" lays them out:
    # where the optional header and its data directories are, what each
    # directory points to, and the section table. Raises Fledge::Error for
    # bytes that are not a PE32 or PE32+ program.
    class Headers # :nodoc:
      # Where the optional header keeps each field Fledge reads or writes,
      # from its start (the PE specification's section 3.4).
      OPTIONAL_FIELDS = {
        initialized_data: 8,
        section_alignment: 32,
        file_alignment: 36,
        image_size: 56,
        checksum: 64,
        subsystem: 68,
      }.freeze

      # A section header: its index among the headers, name, virtual size
      # and address, and the size and file offset of its raw data.
      Section = Data.define(:index, :name, :size, :address, :raw_size, :raw)

      # Every section, in the order the section table lists them.
      attr_reader :sections

      # How many data directories the optional header has.
      attr_reader :directory_count

      def initialize(bytes)
        @bytes = bytes
        raise Error, "is not a Windows program" unless @bytes.start_with?("MZ") && @bytes.bytesize >= 0x40

        @pe = u32(0x3C)
        raise Error, "is not a Windows program" unless @bytes.byteslice(@pe, 4) == "PE\0\0".b

        @optional = @pe + 24
        magic = u16(@optional)
        raise Error, "is not a Windows program it can read (optional header magic 0x#{magic.to_s(16)})" unless [0x10B, 0x20B].include?(magic)

        @directories = @optional + ((magic == 0x20B) ? 112 : 96)
        @directory_count = u32(@directories - 4)
        @sections = Array.new(u16(@pe + 6)) { |index| read_section(index) }
      end

      # Where the optional header keeps the field +name+.
      def field(name)
        @optional + OPTIONAL_FIELDS.fetch(name)
      end

      # Where data directory +index+ is.
      def directory_offset(index)
        @directories + (index * 8)
      end

      # The RVA and size data directory +index+ gives, or zeros for one
      # past the optional header's count.
      def directory(index)
        return [0, 0] if index >= @directory_count

        pair(directory_offset(index))
      end

      # Where the header of section +index+ is.
      def section_offset(index)
        @optional + u16(@pe + 20) + (index * 40)
      end

      def u16(at)
        @bytes.byteslice(at, 2).to_s.unpack1("v").to_i
      end

      def u32(at)
        @bytes.byteslice(at, 4).to_s.unpack1("V").to_i
      end

      # The two 32-bit values at +at+.
      def pair(at)
        [u32(at), u32(at + 4)]
      end

      private def read_section(index)
        at = section_offset(index)
        name = @bytes.byteslice(at, 8).to_s.delete("\0")
        Section.new(index:, name:, size: u32(at + 8), address: u32(at + 12), raw_size: u32(at + 16), raw: u32(at + 20))
      end
    end
  end
end
