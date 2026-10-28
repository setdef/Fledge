# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from test/support/binaries.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
# Writes the smallest files each executable format allows that still
# carry what the license audit reads: the shared libraries a file needs,
# and some bytes of payload, such as a version string. They follow each
# format's specification byte for byte (the ELF gABI, the PE/COFF
# specification, Apple's mach-o/loader.h), so the audit reads them as it
# reads a real compiler's output, on any computer the tests run on.
module Binaries
  # An ELF64 shared object whose dynamic section names +needed+ and
  # +rpath+, followed by +payload+, and that needs, from libc.so.6, the
  # symbol versions in +versions+ (a .gnu.version_r section, as the GNU
  # linker writes one), such as "GLIBC_2.34".
  def self.elf(needed: [], rpath: nil, payload: "", versions: [])
    strings = +"\0"
    offset = lambda do |text|
      at = strings.bytesize
      strings << text << "\0"
      at
    end
    entries = needed.map { |library| [1, offset.call(library)] }
    entries << [15, offset.call(rpath)] if rpath
    entries << [0, 0]
    dynamic = entries.map { |tag, value| [tag, value].pack("Q<Q<") }.join
    verneed = versions.empty? ? "" : version_needs(offset.call("libc.so.6"), versions.map { |version| offset.call(version) })
    strings_at = 64
    dynamic_at = strings_at + strings.bytesize
    verneed_at = dynamic_at + dynamic.bytesize
    payload_at = verneed_at + verneed.bytesize
    sections_at = payload_at + payload.bytesize
    header = ["\x7FELF".b, 2, 1, 1, 0, "\0" * 8, 3, 62, 1, 0, 0, sections_at, 0, 64, 0, 0, 64, verneed.empty? ? 3 : 4, 0]
      .pack("a4CCCCa8S<S<L<Q<Q<Q<L<S<S<S<S<S<S<")
    section = -> (type, at, size, link, info = 0) { [0, type, 0, 0, at, size, link, info, 1, 0].pack("L<L<Q<Q<Q<Q<L<L<Q<Q<") }
    [
      header,
      strings,
      dynamic,
      verneed,
      payload.b,
      section.call(0, 0, 0, 0),
      section.call(3, strings_at, strings.bytesize, 0),
      section.call(6, dynamic_at, dynamic.bytesize, 1),
      *(verneed.empty? ? [] : [section.call(0x6FFFFFFE, verneed_at, verneed.bytesize, 1, 1)]),
    ].map(&:b).join
  end

  # One Elf64_Verneed for the file at string +file+, then an Elf64_Vernaux
  # for each version at the strings +names+ (the ELF symbol versioning
  # specification, as glibc's elf.h lays them out).
  def self.version_needs(file, names)
    need = [1, names.size, file, 16, 0].pack("S<S<L<L<L<")
    aux = names.each_with_index.map { |name, index| [0, 0, index + 2, name, (index == names.size - 1) ? 0 : 16].pack("L<S<S<L<L<") }
    need + aux.join
  end

  # A PE32+ DLL that imports +needed+, followed by +payload+ (where a
  # test can put an embedded manifest).
  def self.pe(needed: [], payload: "")
    dos = "MZ".b.ljust(0x3C, "\0") + [0x40].pack("L<")
    coff = ["PE\0\0".b, 0x8664, 1, 0, 0, 0, 240, 0x2022].pack("a4S<S<L<L<L<S<S<")
    directories = Array.new(16) { |index| (index == 1) ? [0x1000, 20 * (needed.size + 1)] : [0, 0] }
    optional = [0x20B].pack("S<").ljust(112, "\0") + directories.flatten.pack("L<*")
    section = [".idata".b, 0x400, 0x1000, 0x400, 0x400, 0, 0, 0, 0, 0xC0000040].pack("a8L<L<L<L<L<L<S<S<L<")
    names = +""
    descriptors = needed.map do |library|
      rva = 0x1000 + 0x100 + names.bytesize
      names << library << "\0"
      [0, 0, 0, rva, 0].pack("L<5")
    end
    idata = (descriptors.join + ("\0" * 20)).ljust(0x100, "\0") + names
    [(dos + coff + optional + section).ljust(0x400, "\0"), idata.ljust(0x400, "\0"), payload.b].map(&:b).join
  end

  # A 64-bit Mach-O dylib that loads +needed+, followed by +payload+,
  # built for macOS +minos+ (an LC_BUILD_VERSION, as clang and rustc
  # write one) when it is given, such as "14.0".
  def self.macho(needed: [], payload: "", minos: nil)
    commands = needed.map do |library|
      size = (24 + library.bytesize + 1 + 7) / 8 * 8
      [0xC, size, 24, 0, 0, 0].pack("L<6") + library.b.ljust(size - 24, "\0")
    end
    if minos
      major, minor = minos.split(".").map(&:to_i)
      commands << [0x32, 24, 1, (major << 16) | (minor.to_i << 8), 26 << 16, 0].pack("L<6")
    end
    header = [0xFEEDFACF, 0x0100000C, 0, 6, commands.size, commands.sum(&:bytesize), 0, 0].pack("L<8")
    [header, *commands, payload.b].map(&:b).join
  end
end
