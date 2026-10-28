# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from tasks/license_audit/binary.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
module Fledge
  class Binary
    # An ELF file's section headers, read for what Fledge asks of them:
    # the dynamic section's needed libraries and search paths (what
    # <tt>readelf -d</tt> prints) and the glibc symbol versions the file
    # needs (<tt>readelf -V</tt>). It reads 32- and 64-bit files of either
    # byte order, as the ELF header's identification bytes say.
    class Elf < Reader # :nodoc:
      # The ELF dynamic tag that names a needed library.
      DT_NEEDED = 1

      # The ELF dynamic tag of a search path the loader tries first.
      DT_RPATH = 15

      # The ELF dynamic tag of a search path the loader tries after
      # LD_LIBRARY_PATH.
      DT_RUNPATH = 29

      # The ELF section type of the dynamic section.
      SHT_DYNAMIC = 6

      # The ELF section of the symbol versions a file needs from the
      # libraries it loads (SHT_GNU_verneed, in glibc's elf.h).
      SHT_GNU_VERNEED = 0x6FFFFFFE

      # A section header: its type, the file offset and size of its
      # contents, and the index of the section it links to (a string
      # table, for the sections Fledge reads).
      Section = Data.define(:type, :offset, :size, :link)

      # Where a 32-bit file's ELF header keeps its section headers' offset,
      # size, and count, and where each section header keeps its offset,
      # size, and link.
      ELF32 = { shoff: 0x20, shentsize: 0x2E, shnum: 0x30, offset: 16, size: 20, link: 24 }.freeze

      # The same, for a 64-bit file.
      ELF64 = { shoff: 0x28, shentsize: 0x3A, shnum: 0x3C, offset: 24, size: 32, link: 40 }.freeze

      def initialize(bytes)
        super
        wide = bytes.getbyte(4) == 2
        little = bytes.getbyte(5) == 1
        @layout = wide ? ELF64 : ELF32
        @word_size = wide ? 8 : 4
        @word = wide ? (little ? "Q<" : "Q>") : (little ? "L<" : "L>")
        @half = little ? "S<" : "S>"
        @long = little ? "L<" : "L>"
      end

      # The libraries the dynamic section needs, and its search paths.
      def links
        needed = [] # : Array[String]
        rpaths = [] # : Array[String]
        sections_of(SHT_DYNAMIC).each do |dynamic|
          each_dynamic_string(dynamic) { |tag, text| (tag == DT_NEEDED) ? needed << text : rpaths << text }
        end
        [needed, rpaths]
      end

      # The newest <tt>GLIBC_X.Y</tt> version the file needs, as X.Y.
      def glibc_minimum
        versions = sections_of(SHT_GNU_VERNEED).flat_map do |section|
          needed_versions(section.offset, strings_of(section))
        end
        versions.filter_map { |name| name[/\AGLIBC_(\d+(?:\.\d+)+)\z/, 1] }.max_by { |version| Gem::Version.new(version) }
      end

      private def sections
        @sections ||= begin
          offset = word(@layout.fetch(:shoff))
          size = number(@layout.fetch(:shentsize), 2, @half)
          Array.new(number(@layout.fetch(:shnum), 2, @half)) { |index| section(offset + (index * size)) }
        end
      end

      private def sections_of(type)
        sections.select { |section| section.type == type }
      end

      # Where the string table +section+ links to begins.
      private def strings_of(section)
        sections.fetch(section.link).offset
      end

      private def section(at)
        Section.new(type: number(at + 4, 4, @long), offset: word(at + @layout.fetch(:offset)),
          size: word(at + @layout.fetch(:size)), link: number(at + @layout.fetch(:link), 4, @long))
      end

      # The address-sized number at +at+.
      private def word(at)
        number(at, @word_size, @word)
      end

      # Yields the tag and string of each entry of +dynamic+ that names a
      # library or a search path, up to the DT_NULL that ends it.
      private def each_dynamic_string(dynamic)
        strings = strings_of(dynamic)
        entry = @word_size * 2
        (dynamic.size / entry).times do |index|
          at = dynamic.offset + (index * entry)
          tag = word(at)
          break if tag.zero?
          next unless [DT_NEEDED, DT_RPATH, DT_RUNPATH].include?(tag)

          yield tag, c_string(strings + word(at + @word_size))
        end
      end

      # The version names of each Elf_Verneed at +at+ and its Elf_Vernaux
      # entries, whose names are in the string table at +strings+.
      private def needed_versions(at, strings)
        names = [] # : Array[String]
        loop do
          names.concat(auxiliary_names(at, strings))
          step = number(at + 12, 4, @long)
          return names if step.zero?

          at += step
        end
      end

      # The names of the Elf_Vernaux entries of the Elf_Verneed at +at+.
      private def auxiliary_names(at, strings)
        aux = at + number(at + 8, 4, @long)
        names = [] # : Array[String]
        number(at + 2, 2, @half).times do
          names << c_string(strings + number(aux + 8, 4, @long))
          step = number(aux + 12, 4, @long)
          break if step.zero?

          aux += step
        end
        names
      end
    end
  end
end
