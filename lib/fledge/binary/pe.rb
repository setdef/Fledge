# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from tasks/license_audit/binary.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
module Fledge
  class Binary
    # A PE file's import and delay import tables, read for the DLLs they
    # name (what <tt>objdump -p</tt> prints), and the dependent assemblies
    # its embedded manifest names.
    class Pe < Reader # :nodoc:
      # The data directory of the import table.
      IMPORTS = 1

      # The data directory of the delay import table.
      DELAY_IMPORTS = 13

      # A section's virtual address and size, and the file offset of its
      # raw data.
      Section = Data.define(:address, :size, :raw)

      # Whether +bytes+, which begin with MZ, have a PE header where their
      # DOS header says.
      def self.pe?(bytes)
        header = bytes.byteslice(0x3C, 4).to_s.unpack1("L<").to_i
        bytes.byteslice(header, 4) == "PE\0\0".b
      end

      def initialize(bytes)
        super
        coff = number(0x3C, 4, "L<") + 4
        @optional = coff + 20
        @section_table = @optional + number(coff + 16, 2, "S<")
        @section_count = number(coff + 2, 2, "S<")
        @directories = @optional + ((number(@optional, 2, "S<") == 0x20B) ? 112 : 96)
      end

      # The DLLs both import tables name, once each.
      def needed
        (names(IMPORTS, 20, 12) + names(DELAY_IMPORTS, 32, 4)).uniq
      end

      # The assemblies the embedded manifest depends on.
      def assemblies
        @bytes.scan(/<dependentAssembly>\s*<assemblyIdentity[^>]*name="([^"]+)"/m).flatten.map(&:to_s).uniq
      end

      private def sections
        @sections ||= Array.new(@section_count) do |index|
          base = @section_table + (index * 40)
          size = [number(base + 8, 4, "L<"), number(base + 16, 4, "L<")].max.to_i
          Section.new(address: number(base + 12, 4, "L<"), size:, raw: number(base + 20, 4, "L<"))
        end
      end

      # The file offset of the virtual address +rva+, or nil when no
      # section holds it.
      private def offset_of(rva)
        section = sections.find { |candidate| rva >= candidate.address && rva < candidate.address + candidate.size }
        section && (rva - section.address + section.raw)
      end

      # The DLL names the table of +size+-byte import descriptors in data
      # directory +directory+ holds, each naming its DLL by an RVA
      # +name_at+ bytes into it.
      private def names(directory, size, name_at)
        rva = number(@directories + (directory * 8), 4, "L<")
        return [] if rva.zero?

        offset = offset_of(rva) or return []
        names = [] # : Array[String]
        loop do
          descriptor = @bytes.byteslice(offset, size)
          break if descriptor.nil? || descriptor.bytesize < size || descriptor.each_byte.all?(&:zero?)

          name = offset_of(descriptor.byteslice(name_at, 4).to_s.unpack1("L<").to_i)
          names << c_string(name) if name
          offset += size
        end
        names
      end
    end
  end
end
