# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "error"

module Fledge
  # A Windows program whose resources Fledge rewrites: the icon and
  # version information Explorer, the taskbar, and Task Manager show.
  #
  # Windows reads a program's icon and its name, version, and publisher
  # from resources inside the program itself (decision 18). The launcher
  # is compiled once for every app, by Fledge's CI, so each app's
  # resources go into its copy when <tt>fledge build</tt> runs, on
  # whatever computer runs it, Linux and macOS included. Electron's rcedit
  # does this with Windows' own UpdateResource, which only Windows has.
  #
  # This class reads a PE32 or PE32+ program as Microsoft's "PE Format"
  # specification lays it out, reads its resource directory (section
  # 6.9, "The .rsrc Section"), and writes a copy whose resource section
  # holds the resources it is given. The new section replaces the old one
  # where it was; the sections after it, which may only be base
  # relocations (+.reloc+, which nothing in the program points into and
  # which point only at other sections), move up to make room, and the
  # headers that describe them follow. A program with an Authenticode
  # signature is refused, since changing it would break the signature:
  # resources go in before any signing.
  #
  # Use it to give a built app's program its icon and version
  # information.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   program = Fledge::WindowsProgram.new(File.binread("launcher.exe"))
  #   resources = program.resources # => { [24, 1, 1033] => "<?xml ..." }
  #   resources[[16, 1, 1033]] = version_info
  #   File.binwrite("MyCoolApp.exe", program.with_resources(resources))
  #--
  # SPDX-SnippetEnd
  #++
  class WindowsProgram
    # The resource type of an icon image (winuser.h).
    RT_ICON = 3

    # The resource type of an icon group, which lists an icon's images.
    RT_GROUP_ICON = 14

    # The resource type of version information.
    RT_VERSION = 16

    # The resource type of an application manifest.
    RT_MANIFEST = 24

    # The data directory of the resources.
    RESOURCE_DIRECTORY = 2

    # The data directory of the Authenticode certificate table.
    CERTIFICATE_DIRECTORY = 4

    # The data directory of the base relocations.
    RELOCATION_DIRECTORY = 5

    # The Subsystem of a program Windows gives a console.
    CONSOLE = 3

    # The Subsystem of a program Windows gives no console (a GUI program).
    GUI = 2

    # Reads the program in +bytes+. Raises Fledge::Error for anything that
    # is not a PE program.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::WindowsProgram.new(File.binread("launcher.exe")).subsystem # => 3
    #--
    # SPDX-SnippetEnd
    #++
    def initialize(bytes)
      @bytes = bytes.b
      raise Error, "is not a Windows program" unless @bytes.start_with?("MZ") && @bytes.bytesize >= 0x40

      @pe = @bytes.byteslice(0x3C, 4).to_s.unpack1("V").to_i
      raise Error, "is not a Windows program" unless @bytes.byteslice(@pe, 4) == "PE\0\0".b

      read_headers
    end

    # The Subsystem field of the optional header: CONSOLE or GUI.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   program.subsystem == Fledge::WindowsProgram::GUI
    #--
    # SPDX-SnippetEnd
    #++
    def subsystem
      u16(@optional + 68)
    end

    # Every resource, by its type, name, and language, each an Integer ID
    # or a String name, as a Hash of binary Strings in the order the
    # resource directory lists them.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   program.resources.keys # => [[24, 1, 1033]]
    #--
    # SPDX-SnippetEnd
    #++
    def resources
      section = resource_section
      return {} unless section

      found = {} # : Hash[[Integer | String, Integer | String, Integer | String], String]
      each_entry(section, 0) do |type, type_offset|
        each_entry(section, type_offset) do |name, name_offset|
          each_entry(section, name_offset) do |language, data_offset|
            rva, size = pair(section.raw + data_offset)
            found[[type, name, language]] = @bytes.byteslice(section.raw + rva - section.address, size).to_s
          end
        end
      end
      found
    end

    # A copy of the program whose resource section holds +resources+
    # (keyed as #resources returns them) and nothing else. Raises
    # Fledge::Error when the program has no resource section, a signature,
    # data after its last section, or sections after its resources that
    # Fledge cannot move.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   program.with_resources(program.resources) # the same resources, rewritten
    #--
    # SPDX-SnippetEnd
    #++
    def with_resources(resources)
      check_rewritable
      section = resource_section or raise Error, "has no resource section to rewrite"
      later = @sections.select { |other| other.raw > section.raw }
      unless later.all? { |other| other.name == ".reloc" }
        raise Error, "has sections after its resources (#{later.map(&:name).join(', ')}) that Fledge cannot move"
      end

      table = ResourceTable.new(resources).bytes(section.address)
      rewrite(section, table, later)
    end

    # A section header: its index among the headers, name, virtual size
    # and address, and the size and file offset of its raw data.
    Section = Data.define(:index, :name, :size, :address, :raw_size, :raw) # :nodoc:

    private def read_headers
      count = u16(@pe + 6)
      optional_size = u16(@pe + 20)
      @optional = @pe + 24
      magic = u16(@optional)
      raise Error, "is not a Windows program it can read (optional header magic 0x#{magic.to_s(16)})" unless [0x10B, 0x20B].include?(magic)

      @directories = @optional + ((magic == 0x20B) ? 112 : 96)
      @directory_count = u32(@directories - 4)
      table = @optional + optional_size
      @sections = Array.new(count) do |index|
        at = table + (index * 40)
        name = @bytes.byteslice(at, 8).to_s.delete("\0")
        Section.new(index:, name:, size: u32(at + 8), address: u32(at + 12), raw_size: u32(at + 16), raw: u32(at + 20))
      end
    end

    private def directory(index)
      return [0, 0] if index >= @directory_count

      pair(@directories + (index * 8))
    end

    private def resource_section
      rva, size = directory(RESOURCE_DIRECTORY)
      return nil if rva.zero? || size.zero?

      @sections.find { |section| section.address == rva } or raise Error, "has a resource directory that does not begin a section"
    end

    private def check_rewritable
      raise Error, "is signed; its resources must change before it is signed, not after" unless directory(CERTIFICATE_DIRECTORY)[1].zero?

      last = @sections.max_by { |section| section.raw + section.raw_size }
      ends = last ? last.raw + last.raw_size : 0
      raise Error, "has data after its last section, which Fledge cannot move" if @bytes.bytesize > ends
    end

    # Yields the ID or name of each entry of the resource directory at
    # +offset+ in +section+, and the offset its entry points to.
    private def each_entry(section, offset)
      (u16(section.raw + offset + 12) + u16(section.raw + offset + 14)).times do |index|
        name, target = pair(section.raw + offset + 16 + (index * 8))
        key = name.anybits?(0x8000_0000) ? resource_name(section, name & 0x7FFF_FFFF) : name
        yield key, target & 0x7FFF_FFFF
      end
    end

    private def resource_name(section, offset)
      length = u16(section.raw + offset)
      @bytes.byteslice(section.raw + offset + 2, length * 2).to_s.force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
    end

    # The program with +table+ as the raw data of +section+, and the
    # sections in +later+ moved to follow it.
    private def rewrite(section, table, later)
      file_alignment, section_alignment = u32(@optional + 36), u32(@optional + 32)
      raw_size = align(table.bytesize, file_alignment)
      out = @bytes.byteslice(0, section.raw).to_s + table.ljust(raw_size, "\0")
      address = align(section.address + table.bytesize, section_alignment)
      write_section(out, section, size: table.bytesize, address: section.address, raw_size:, raw: section.raw)
      write_directory(out, RESOURCE_DIRECTORY, section.address, table.bytesize)
      later.sort_by(&:raw).each do |moved|
        raw = out.bytesize
        out << @bytes.byteslice(moved.raw, moved.raw_size).to_s
        move_directories(out, moved, address)
        write_section(out, moved, size: moved.size, address:, raw_size: moved.raw_size, raw:)
        address = align(address + moved.size, section_alignment)
      end
      put32(out, @optional + 56, address)
      put32(out, @optional + 8, u32(@optional + 8) + raw_size - section.raw_size)
      put32(out, @optional + 64, WindowsProgram.checksum(out, @optional + 64)) unless u32(@optional + 64).zero?
      out
    end

    # Points every data directory inside +moved+ at its new +address+.
    private def move_directories(out, moved, address)
      @directory_count.times do |index|
        rva, size = directory(index)
        next unless rva >= moved.address && rva < moved.address + [moved.size, moved.raw_size].max

        write_directory(out, index, rva - moved.address + address, size)
      end
    end

    private def write_section(out, section, size:, address:, raw_size:, raw:)
      at = @optional + u16(@pe + 20) + (section.index * 40) + 8
      out.bytesplice(at, 16, [size, address, raw_size, raw].pack("V4"))
    end

    private def write_directory(out, index, rva, size)
      out.bytesplice(@directories + (index * 8), 8, [rva, size].pack("V2"))
    end

    # The PE checksum of +bytes+, whose checksum field is at +field+: the
    # 16-bit ones' complement sum of the file, skipping the field, plus
    # the file's length (as imagehlp's CheckSumMappedFile computes it).
    def self.checksum(bytes, field)
      sum = 0
      padded = bytes.bytesize.odd? ? "#{bytes}\0" : bytes
      padded.unpack("v*").each_with_index do |word, index|
        next if [field / 2, (field / 2) + 1].include?(index)

        sum += word.to_i
        sum = (sum & 0xFFFF) + (sum >> 16)
      end
      sum = (sum & 0xFFFF) + (sum >> 16)
      sum + bytes.bytesize
    end

    private def align(value, alignment)
      ((value + alignment - 1) / alignment) * alignment
    end

    private def u16(at)
      @bytes.byteslice(at, 2).to_s.unpack1("v").to_i
    end

    private def u32(at)
      @bytes.byteslice(at, 4).to_s.unpack1("V").to_i
    end

    # The two 32-bit values at +at+.
    private def pair(at)
      [u32(at), u32(at + 4)]
    end

    private def put32(out, at, value)
      out.bytesplice(at, 4, [value].pack("V"))
    end

    # Writes a resource section: the three levels of directories Windows
    # searches (type, name, language), then the names, the data entries,
    # and the data, each piece aligned as the PE specification asks.
    class ResourceTable # :nodoc:
      def initialize(resources)
        @tree = {} # : Hash[Integer | String, Hash[Integer | String, Hash[Integer | String, String]]]
        resources.each do |(type, name, language), data|
          ((@tree[type] ||= {})[name] ||= {})[language] = data
        end
      end

      # The section's bytes, for a section at virtual address +address+.
      def bytes(address)
        types = sorted(@tree.keys)
        names = types.map { |type| [type, sorted(@tree.fetch(type).keys)] } #: Array[[Integer | String, Array[Integer | String]]]
        languages = names.flat_map do |type, keys|
          keys.map { |name| [[type, name], sorted(@tree.fetch(type).fetch(name).keys)] }
        end #: Array[[[Integer | String, Integer | String], Array[Integer | String]]]
        type_at = 16 + (types.size * 8)
        name_at = type_at + names.sum { |_, keys| 16 + (keys.size * 8) }
        strings_at = name_at + languages.sum { |_, keys| 16 + (keys.size * 8) }
        strings, string_offsets = name_strings(types + names.flat_map(&:last), strings_at)
        entries_at = align(strings_at + strings.bytesize, 4)
        leaves = languages.flat_map { |(type, name), keys| keys.map { |language| @tree.fetch(type).fetch(name).fetch(language) } }
        data_at = entries_at + (leaves.size * 16)
        placed = leaves.map do |data|
          at = align(data_at, 8)
          data_at = at + data.bytesize
          at
        end

        out = directory(types, string_offsets) { |index| 0x8000_0000 | (type_at + names.first(index).sum { |_, keys| 16 + (keys.size * 8) }) }
        before = 0
        names.each do |_, keys|
          out << directory(keys, string_offsets) do |index|
            0x8000_0000 | (name_at + languages.first(before + index).sum { |_, langs| 16 + (langs.size * 8) })
          end
          before += keys.size
        end
        leaf = 0
        languages.each do |_, keys|
          first = leaf
          out << directory(keys, string_offsets) { |index| entries_at + ((first + index) * 16) }
          leaf += keys.size
        end
        out << strings
        out = out.ljust(entries_at, "\0")
        leaves.each_with_index { |data, index| out << [address + placed.fetch(index), data.bytesize, 0, 0].pack("V4") }
        leaves.each_with_index { |data, index| out = out.ljust(placed.fetch(index), "\0") << data }
        out
      end

      # The keys of a directory in the order Windows' binary search through
      # it expects: names first, case-insensitively, then IDs.
      private def sorted(keys)
        names, ids = split(keys)
        [*names.sort_by(&:upcase), *ids.sort]
      end

      # +keys+ as its names and its IDs.
      private def split(keys)
        names = [] # : Array[String]
        ids = [] # : Array[Integer]
        keys.each do |key|
          case key
          when String then names << key
          else ids << key
          end
        end
        [names, ids]
      end

      # The names among +keys+, each as a length and UTF-16 characters,
      # from +at+, and where each one is.
      private def name_strings(keys, at)
        strings = +"".b
        offsets = {} # : Hash[String, Integer]
        split(keys).first.uniq.each do |name|
          offsets[name] = at + strings.bytesize
          utf16 = name.encode(Encoding::UTF_16LE).b
          strings << [utf16.bytesize / 2].pack("v") << utf16
        end
        [strings, offsets]
      end

      # A directory of +keys+, each pointing where the block says.
      private def directory(keys, string_offsets)
        named = keys.count { |key| key.is_a?(String) }
        header = [0, 0, 0, 0, named, keys.size - named].pack("V2v4")
        header + keys.each_with_index.map do |key, index|
          name = key.is_a?(String) ? (0x8000_0000 | string_offsets.fetch(key)) : key
          [name, yield(index)].pack("V2")
        end.join
      end

      private def align(value, alignment)
        ((value + alignment - 1) / alignment) * alignment
      end
    end
  end
end
