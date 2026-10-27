# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from tasks/license_audit/binary.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
module Fledge
  # What a compiled file links: its format and the shared libraries the
  # system loader must find for it, read from the file itself.
  #
  # Fledge copies compiled code into every app: the runtime's, and the
  # native gems an app's Gemfile.lock locks. What that code links decides
  # what a license asks of the app's developer, since an LGPL library may
  # ship only as a separate shared library that another file loads, never
  # compiled into it (decision 8 in <tt>doc/contributors/decisions.md</tt>).
  # Tools that answer the question (readelf, otool, objdump) each read one
  # format, on one operating system.
  #
  # This class reads ELF's dynamic section (what <tt>readelf -d</tt>
  # prints), Mach-O's dylib load commands (<tt>otool -L</tt>), and PE's
  # import and delay import tables (<tt>objdump -p</tt>), plus the
  # dependent assemblies a Windows manifest embedded in a PE names, in
  # Ruby, so that one computer reads all four platforms' files with the
  # same code, and a test can feed it bytes. A static archive (ar) counts
  # as a binary that links nothing, because what matters about it is that
  # its code would be copied into whatever links it.
  #
  # Use it to audit a runtime (ADR 004) or an app's native gems (ADR 005).
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   binary = Fledge::Binary.read("lib/sqlite3/4.0/sqlite3_native.so")
  #   binary.format # => :elf
  #   binary.needed # => ["libm.so.6", "libz.so.1", "libdl.so.2", "libpthread.so.0", "libc.so.6"]
  #
  #   Fledge::Binary.parse("puts 'hello'\n") # => nil
  #--
  # SPDX-SnippetEnd
  #++
  class Binary < Data.define(:format, :needed, :rpaths, :assemblies)
    ##
    # :attr_reader: format
    # The file's format: <tt>:elf</tt>, <tt>:macho</tt>, <tt>:pe</tt>, or
    # <tt>:archive</tt>.

    ##
    # :attr_reader: needed
    # The shared libraries the file needs, as the file names them.

    ##
    # :attr_reader: rpaths
    # The folders an ELF or Mach-O file asks the loader to search.

    ##
    # :attr_reader: assemblies
    # The side-by-side assemblies a PE's embedded manifest names.

    # The first bytes of an ELF file.
    ELF_MAGIC = "\x7FELF".b
    # The first bytes of a static archive.
    AR_MAGIC = "!<arch>\n".b
    # The first bytes of a 64-bit and a 32-bit little-endian Mach-O file.
    MACHO_MAGICS = ["\xCF\xFA\xED\xFE".b, "\xCE\xFA\xED\xFE".b].freeze
    # The first bytes of a universal (fat) Mach-O file.
    FAT_MAGIC = "\xCA\xFE\xBA\xBE".b

    # The ELF dynamic tag that names a needed library.
    DT_NEEDED = 1

    # The ELF dynamic tag of a search path the loader tries first.
    DT_RPATH = 15

    # The ELF dynamic tag of a search path the loader tries after
    # LD_LIBRARY_PATH.
    DT_RUNPATH = 29

    # The ELF section type of the dynamic section.
    SHT_DYNAMIC = 6

    # The Mach-O load commands that name a dylib: LC_LOAD_DYLIB,
    # LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LAZY_LOAD_DYLIB, and
    # LC_LOAD_UPWARD_DYLIB.
    LC_DYLIBS = [0xC, 0x80000018, 0x8000001F, 0x20, 0x80000023].freeze
    # The Mach-O load command that adds a search path.
    LC_RPATH = 0x8000001C

    # The Binary in the file at +path+, or nil when it holds no code.
    # Raises ArgumentError when the file looks like a binary but cannot be
    # read as one.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Binary.read("bin/ruby").needed # => ["libcrypt.so.2", "libm.so.6", "libc.so.6"]
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(path)
      return nil if File.symlink?(path) || !File.file?(path)

      parse(File.binread(path))
    rescue RangeError, ArgumentError, TypeError, NoMethodError => e
      raise ArgumentError, "#{path}: unreadable binary (#{e.message})"
    end

    # The Binary +bytes+ hold, or nil when they hold no code.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Binary.parse("!<arch>\nfoo.o/").format # => :archive
    #--
    # SPDX-SnippetEnd
    #++
    def self.parse(bytes)
      bytes = bytes.b
      if bytes.start_with?(ELF_MAGIC) then elf(bytes)
      elsif MACHO_MAGICS.any? { |magic| bytes.start_with?(magic) } then macho(bytes, 0)
      elsif bytes.start_with?(FAT_MAGIC) && number(bytes, 4, 4, "N") < 32 then fat(bytes)
      elsif bytes.start_with?("MZ") && pe?(bytes) then pe(bytes)
      elsif bytes.start_with?(AR_MAGIC) then new(format: :archive, needed: [], rpaths: [], assemblies: [])
      end
    end

    private_class_method def self.elf(bytes) # :nodoc:
      wide = bytes.getbyte(4) == 2
      little = bytes.getbyte(5) == 1
      word = wide ? (little ? "Q<" : "Q>") : (little ? "L<" : "L>")
      half = little ? "S<" : "S>"
      long = little ? "L<" : "L>"
      shoff = number(bytes, wide ? 0x28 : 0x20, wide ? 8 : 4, word)
      shentsize = number(bytes, wide ? 0x3A : 0x2E, 2, half)
      shnum = number(bytes, wide ? 0x3C : 0x30, 2, half)
      sections = Array.new(shnum) { |index| elf_section(bytes, shoff + (index * shentsize), wide, word, long) }
      needed = [] # : Array[String]
      rpaths = [] # : Array[String]
      sections.select { |section| section.fetch(:type) == SHT_DYNAMIC }.each do |dynamic|
        strings = sections.fetch(dynamic.fetch(:link)).fetch(:offset)
        entry = wide ? 16 : 8
        (dynamic.fetch(:size) / entry).times do |index|
          at = dynamic.fetch(:offset) + (index * entry)
          tag = number(bytes, at, entry / 2, word)
          break if tag.zero?

          next unless [DT_NEEDED, DT_RPATH, DT_RUNPATH].include?(tag)

          text = c_string(bytes, strings + number(bytes, at + (entry / 2), entry / 2, word))
          (tag == DT_NEEDED) ? needed << text : rpaths << text
        end
      end
      new(format: :elf, needed:, rpaths:, assemblies: [])
    end

    private_class_method def self.elf_section(bytes, at, wide, word, long) # :nodoc:
      if wide
        {
type: number(bytes, at + 4, 4, long),
offset: number(bytes, at + 24, 8, word),
size: number(bytes, at + 32, 8, word),
link: number(bytes, at + 40, 4, long),
}
      else
        {
type: number(bytes, at + 4, 4, long),
offset: number(bytes, at + 16, 4, word),
size: number(bytes, at + 20, 4, word),
link: number(bytes, at + 24, 4, long),
}
      end
    end

    private_class_method def self.macho(bytes, base) # :nodoc:
      wide = bytes.byteslice(base, 4) == MACHO_MAGICS.first
      ncmds = number(bytes, base + 16, 4, "L<")
      offset = base + (wide ? 32 : 28)
      needed = [] # : Array[String]
      rpaths = [] # : Array[String]
      ncmds.times do
        cmd = number(bytes, offset, 4, "L<")
        size = number(bytes, offset + 4, 4, "L<")
        if LC_DYLIBS.include?(cmd)
          needed << c_string(bytes, offset + number(bytes, offset + 8, 4, "L<"))
        elsif cmd == LC_RPATH
          rpaths << c_string(bytes, offset + number(bytes, offset + 8, 4, "L<"))
        end
        offset += size
      end
      new(format: :macho, needed:, rpaths:, assemblies: [])
    end

    # A universal binary: the first architecture's slice.
    private_class_method def self.fat(bytes) # :nodoc:
      macho(bytes, number(bytes, 16, 4, "N"))
    end

    private_class_method def self.pe?(bytes) # :nodoc:
      header = number(bytes, 0x3C, 4, "L<")
      bytes.byteslice(header, 4) == "PE\0\0".b
    end

    private_class_method def self.pe(bytes) # :nodoc:
      coff = number(bytes, 0x3C, 4, "L<") + 4
      section_count = number(bytes, coff + 2, 2, "S<")
      optional_size = number(bytes, coff + 16, 2, "S<")
      optional = coff + 20
      plus = number(bytes, optional, 2, "S<") == 0x20B
      directories = optional + (plus ? 112 : 96)
      sections = Array.new(section_count) do |index|
        base = optional + optional_size + (index * 40)
        size = [number(bytes, base + 8, 4, "L<"), number(bytes, base + 16, 4, "L<")].max.to_i
        { address: number(bytes, base + 12, 4, "L<"), size:, raw: number(bytes, base + 20, 4, "L<") }
      end
      at = lambda do |rva|
        section = sections.find { |candidate| rva >= candidate.fetch(:address) && rva < candidate.fetch(:address) + candidate.fetch(:size) }
        section && (rva - section.fetch(:address) + section.fetch(:raw))
      end
      needed = pe_names(bytes, at, number(bytes, directories + 8, 4, "L<"), 20, 12)
      needed += pe_names(bytes, at, number(bytes, directories + (13 * 8), 4, "L<"), 32, 4)
      assemblies = bytes.scan(/<dependentAssembly>\s*<assemblyIdentity[^>]*name="([^"]+)"/m).flatten.map(&:to_s).uniq
      new(format: :pe, needed: needed.uniq, rpaths: [], assemblies:)
    end

    # The DLL names a table of +size+-byte import descriptors at +rva+
    # holds, each naming its DLL by an RVA +name_at+ bytes into it.
    private_class_method def self.pe_names(bytes, at, rva, size, name_at) # :nodoc:
      return [] if rva.zero?

      offset = at.call(rva) or return []
      names = [] # : Array[String]
      loop do
        descriptor = bytes.byteslice(offset, size)
        break if descriptor.nil? || descriptor.bytesize < size || descriptor.each_byte.all?(&:zero?)

        name = at.call(number(descriptor, name_at, 4, "L<"))
        names << c_string(bytes, name) if name
        offset += size
      end
      names
    end

    # The unsigned number of +size+ bytes at +offset+, in the pack
    # +format+, or 0 past the end.
    private_class_method def self.number(bytes, offset, size, format) # :nodoc:
      bytes.byteslice(offset, size).to_s.unpack1(format).to_i
    end

    private_class_method def self.c_string(bytes, offset) # :nodoc:
      ending = bytes.index("\0".b, offset) || bytes.bytesize
      bytes.byteslice(offset, ending - offset).to_s.force_encoding(Encoding::UTF_8)
    end
  end
end
