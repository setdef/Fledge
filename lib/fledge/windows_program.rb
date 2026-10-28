# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "error"
require_relative "windows_program/headers"
require_relative "windows_program/resource_table"
require_relative "windows_program/rewriter"

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
      @headers = Headers.new(@bytes)
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
      @headers.u16(@headers.field(:subsystem))
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
            rva, size = @headers.pair(section.raw + data_offset)
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
      later = @headers.sections.select { |other| other.raw > section.raw }
      unless later.all? { |other| other.name == ".reloc" }
        raise Error, "has sections after its resources (#{later.map(&:name).join(', ')}) that Fledge cannot move"
      end

      table = ResourceTable.new(resources).bytes(section.address)
      Rewriter.new(@bytes, @headers).rewrite(section, table, later)
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

    private def resource_section
      rva, size = @headers.directory(RESOURCE_DIRECTORY)
      return nil if rva.zero? || size.zero?

      @headers.sections.find { |section| section.address == rva } or raise Error, "has a resource directory that does not begin a section"
    end

    private def check_rewritable
      raise Error, "is signed; its resources must change before it is signed, not after" unless @headers.directory(CERTIFICATE_DIRECTORY)[1].zero?

      last = @headers.sections.max_by { |section| section.raw + section.raw_size }
      ends = last ? last.raw + last.raw_size : 0
      raise Error, "has data after its last section, which Fledge cannot move" if @bytes.bytesize > ends
    end

    # Yields the ID or name of each entry of the resource directory at
    # +offset+ in +section+, and the offset its entry points to.
    private def each_entry(section, offset)
      at = section.raw + offset
      (@headers.u16(at + 12) + @headers.u16(at + 14)).times do |index|
        name, target = @headers.pair(at + 16 + (index * 8))
        key = name.anybits?(0x8000_0000) ? resource_name(section, name & 0x7FFF_FFFF) : name
        yield key, target & 0x7FFF_FFFF
      end
    end

    private def resource_name(section, offset)
      length = @headers.u16(section.raw + offset)
      @bytes.byteslice(section.raw + offset + 2, length * 2).to_s.force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
    end
  end
end
