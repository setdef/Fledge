# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class LicenseAudit
  # What a compiled file links: its format and the shared libraries the
  # system loader must find for it, read from the file itself.
  #
  # The audit reads ELF's dynamic section (what readelf -d prints),
  # Mach-O's dylib load commands (otool -L), and PE's import and delay
  # import tables (objdump -p), plus the dependent assemblies a Windows
  # manifest embedded in a PE names. It reads them in Ruby rather than
  # shelling out so that one Linux runner audits all four runtimes with
  # the same code, and a test can feed it bytes. A static archive (ar)
  # counts as a binary that links nothing, because what matters about it
  # is that its code would be copied into whatever links it.
  class Binary < Data.define(:format, :needed, :rpaths, :assemblies)
    ELF_MAGIC = "\x7FELF".b
    AR_MAGIC = "!<arch>\n".b
    MACHO_MAGICS = ["\xCF\xFA\xED\xFE".b, "\xCE\xFA\xED\xFE".b].freeze
    FAT_MAGIC = "\xCA\xFE\xBA\xBE".b

    DT_NEEDED = 1
    DT_RPATH = 15
    DT_RUNPATH = 29
    SHT_DYNAMIC = 6

    LC_DYLIBS = [0xC, 0x80000018, 0x8000001F, 0x20, 0x80000023].freeze

    # The Binary in the file at +path+, or nil when it holds no code.
    def self.read(path)
      return nil if File.symlink?(path) || !File.file?(path)

      bytes = File.binread(path)
      parse(bytes)
    rescue RangeError, ArgumentError, TypeError, NoMethodError => e
      raise ArgumentError, "#{path}: unreadable binary (#{e.message})"
    end

    # The Binary +bytes+ hold, or nil when they hold no code.
    def self.parse(bytes)
      bytes = bytes.b
      if bytes.start_with?(ELF_MAGIC) then elf(bytes)
      elsif MACHO_MAGICS.any? { |magic| bytes.start_with?(magic) } then macho(bytes, 0)
      elsif bytes.start_with?(FAT_MAGIC) && bytes.byteslice(4, 4).unpack1("N") < 32 then fat(bytes)
      elsif bytes.start_with?("MZ") && pe?(bytes) then pe(bytes)
      elsif bytes.start_with?(AR_MAGIC) then new(format: :archive, needed: [], rpaths: [], assemblies: [])
      end
    end

    def self.elf(bytes)
      wide = bytes.getbyte(4) == 2
      little = bytes.getbyte(5) == 1
      word = wide ? (little ? "Q<" : "Q>") : (little ? "L<" : "L>")
      half = little ? "S<" : "S>"
      long = little ? "L<" : "L>"
      shoff = bytes.byteslice(wide ? 0x28 : 0x20, wide ? 8 : 4).unpack1(word)
      shentsize = bytes.byteslice(wide ? 0x3A : 0x2E, 2).unpack1(half)
      shnum = bytes.byteslice(wide ? 0x3C : 0x30, 2).unpack1(half)
      sections = Array.new(shnum) do |index|
        header = bytes.byteslice(shoff + (index * shentsize), shentsize)
        if wide
          {
            type: header.byteslice(4, 4).unpack1(long),
            offset: header.byteslice(24, 8).unpack1(word),
            size: header.byteslice(32, 8).unpack1(word),
            link: header.byteslice(40, 4).unpack1(long),
          }
        else
          {
            type: header.byteslice(4, 4).unpack1(long),
            offset: header.byteslice(16, 4).unpack1(word),
            size: header.byteslice(20, 4).unpack1(word),
            link: header.byteslice(24, 4).unpack1(long),
          }
        end
      end
      needed = []
      rpaths = []
      sections.select { |section| section[:type] == SHT_DYNAMIC }.each do |dynamic|
        strings = sections.fetch(dynamic[:link])
        entry = wide ? 16 : 8
        (dynamic[:size] / entry).times do |index|
          tag, value = bytes.byteslice(dynamic[:offset] + (index * entry), entry).unpack("#{word}2")
          break if tag.zero?

          text = c_string(bytes, strings[:offset] + value) if [DT_NEEDED, DT_RPATH, DT_RUNPATH].include?(tag)
          needed << text if tag == DT_NEEDED
          rpaths << text if [DT_RPATH, DT_RUNPATH].include?(tag)
        end
      end
      new(format: :elf, needed:, rpaths:, assemblies: [])
    end

    def self.macho(bytes, base)
      wide = bytes.byteslice(base, 4) == MACHO_MAGICS.first
      ncmds = bytes.byteslice(base + 16, 4).unpack1("L<")
      offset = base + (wide ? 32 : 28)
      needed = []
      rpaths = []
      ncmds.times do
        cmd, size = bytes.byteslice(offset, 8).unpack("L<L<")
        if LC_DYLIBS.include?(cmd)
          needed << c_string(bytes, offset + bytes.byteslice(offset + 8, 4).unpack1("L<"))
        elsif cmd == 0x8000001C # LC_RPATH
          rpaths << c_string(bytes, offset + bytes.byteslice(offset + 8, 4).unpack1("L<"))
        end
        offset += size
      end
      new(format: :macho, needed:, rpaths:, assemblies: [])
    end

    # A universal binary: the first architecture's slice.
    def self.fat(bytes)
      macho(bytes, bytes.byteslice(16, 4).unpack1("N"))
    end

    def self.pe?(bytes)
      header = bytes.byteslice(0x3C, 4)&.unpack1("L<")
      !header.nil? && bytes.byteslice(header, 4) == "PE\0\0".b
    end

    def self.pe(bytes)
      header = bytes.byteslice(0x3C, 4).unpack1("L<")
      coff = header + 4
      section_count = bytes.byteslice(coff + 2, 2).unpack1("S<")
      optional_size = bytes.byteslice(coff + 16, 2).unpack1("S<")
      optional = coff + 20
      plus = bytes.byteslice(optional, 2).unpack1("S<") == 0x20B
      directories = optional + (plus ? 112 : 96)
      sections = Array.new(section_count) do |index|
        base = optional + optional_size + (index * 40)
        virtual_size, address, raw_size, raw = bytes.byteslice(base + 8, 16).unpack("L<4")
        { address:, size: [virtual_size, raw_size].max, raw: }
      end
      at = lambda do |rva|
        section = sections.find { |candidate| rva >= candidate[:address] && rva < candidate[:address] + candidate[:size] }
        section && (rva - section[:address] + section[:raw])
      end
      needed = pe_names(bytes, at, bytes.byteslice(directories + 8, 4).unpack1("L<"), 20, 12)
      needed += pe_names(bytes, at, bytes.byteslice(directories + (13 * 8), 4).unpack1("L<"), 32, 4)
      assemblies = bytes.scan(/<dependentAssembly>\s*<assemblyIdentity[^>]*name="([^"]+)"/m).flatten.uniq
      new(format: :pe, needed: needed.uniq, rpaths: [], assemblies:)
    end

    # The DLL names a table of +size+-byte import descriptors at +rva+
    # holds, each naming its DLL by an RVA +name_at+ bytes into it.
    def self.pe_names(bytes, at, rva, size, name_at)
      return [] if rva.zero?

      offset = at.call(rva) or return []
      names = []
      loop do
        descriptor = bytes.byteslice(offset, size)
        break if descriptor.nil? || descriptor.bytesize < size || descriptor.each_byte.all?(&:zero?)

        name = at.call(descriptor.byteslice(name_at, 4).unpack1("L<"))
        names << c_string(bytes, name) if name
        offset += size
      end
      names
    end

    def self.c_string(bytes, offset)
      ending = bytes.index("\0".b, offset) || bytes.bytesize
      bytes.byteslice(offset, ending - offset).force_encoding(Encoding::UTF_8)
    end

    private_class_method :elf, :macho, :fat, :pe?, :pe, :pe_names, :c_string
  end
end
