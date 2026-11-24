# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require_relative "../../lib/fledge/binary"

class RuntimeBuilder
  # The protections against memory-safety attacks that each platform's
  # launcher and bin/ruby are compiled with, the flags that ask for them,
  # and the check that a built program has them
  # (doc/contributors/design/launcher.md, "Hardening").
  #
  # A program that lacks one is refused before the runtime is archived,
  # whatever the compiler's own defaults were: Fledge asks for each
  # protection (COMPILE, LINK), and then reads the built file for it
  # (#missing), with the readers the license audit reads the same file
  # with (Fledge::Binary::Readers), so a change of the build image's
  # compiler cannot drop one unseen.
  #
  # A protection a platform's C library or object format does not have
  # is not in its list, and nothing here pretends otherwise: musl has no
  # fortified calls, Mach-O has no RELRO, no BIND_NOW, and no
  # stack-flag to make non-executable (a Mach-O stack is not executable
  # unless a program asks for it), and PE's stack canary is not in a
  # stripped file to read.
  class Hardening
    # The compiler flags each kind asks for, with what each is for.
    # -fPIE and -fstack-protector-strong: the position-independent code
    # that ASLR needs, and a canary in each function that has an array or
    # takes an address (GCC and Clang both; OpenSSF's "Compiler Options
    # Hardening Guide for C and C++"). -D_FORTIFY_SOURCE: the C library's
    # checked versions of memcpy, strcpy, and the like (glibc's and
    # Apple's headers, only when optimizing, which -O2 does); glibc takes
    # 3 where its compiler is new enough and falls back to 2 where it is
    # not, and a compiler that defines it by default is told to start
    # over, so that the definition is Fledge's.
    COMPILE = {
      glibc: %w[-fPIE -fstack-protector-strong -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3],
      musl: %w[-fPIE -fstack-protector-strong],
      darwin: %w[-fPIE -fstack-protector-strong -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2],
      darwin_objects: [],
      windows: [],
    }.freeze

    # The linker flags each kind asks for. -pie links a position-independent
    # executable; -z relro and -z now make the relocations resolve at
    # start and the GOT read-only afterwards (full RELRO); -z noexecstack
    # marks the stack not executable. On Windows, ASLR (dynamicbase), its
    # 64-bit address space (high-entropy-va), and DEP (nxcompat) are
    # bits of the PE header that the linker sets only when asked, whatever
    # its default.
    LINK = {
      glibc: %w[-pie -Wl,-z,relro,-z,now,-z,noexecstack],
      musl: %w[-pie -Wl,-z,relro,-z,now,-z,noexecstack],
      darwin: %w[-Wl,-pie],
      darwin_objects: [],
      windows: %w[-Wl,--dynamicbase,--high-entropy-va,--nxcompat],
    }.freeze

    # The protections a program of each kind must have, by the name the
    # refusal gives them.
    REQUIRED = {
      glibc: %w[PIE RELRO BIND_NOW non-executable\ stack stack\ protector FORTIFY],
      musl: %w[PIE RELRO BIND_NOW non-executable\ stack stack\ protector],
      darwin: %w[PIE stack\ protector FORTIFY],
      darwin_objects: %w[stack\ protector FORTIFY],
      windows: %w[DYNAMIC_BASE HIGH_ENTROPY_VA NX_COMPAT],
    }.freeze

    # ELF's DT_FLAGS bit DF_BIND_NOW, and DT_FLAGS_1's DF_1_NOW and
    # DF_1_PIE (the gABI's and glibc's elf.h).
    DF_BIND_NOW = 0x8
    DF_1_NOW = 0x1
    DF_1_PIE = 0x08000000

    attr_reader :kind

    # +kind+ is :glibc, :musl, :darwin, :windows, or :darwin_objects (the
    # object files a Mac's programs are linked from, which show whether
    # Fledge's own code was compiled with the flags, where the program
    # also holds libruby's); +readers+ the Fledge::Binary::Readers that
    # read this kind's files.
    def initialize(kind:, readers:)
      raise ArgumentError, "no hardening of #{kind}" unless REQUIRED.key?(kind)

      @kind = kind
      @readers = readers
    end

    # The protections of REQUIRED that the files at +paths+, which are
    # one program or the object files of one, all together lack, by name.
    # Raises when no reader reads a file.
    def missing(*paths)
      have = paths.flat_map { |path| protections(path) }
      REQUIRED.fetch(kind).reject { |name| have.include?(name) }
    end

    # Raises, naming what each of +programs+ lacks, when any lacks a
    # protection. A program is a path, or an array of the paths of the
    # object files it is linked from.
    def check(programs)
      lacking = programs.to_h { |program| [Array(program).join(", "), missing(*program)] }.reject { |_, names| names.empty? }
      return if lacking.empty?

      raise lacking.map { |path, names| "#{path} lacks #{names.join(', ')}" }.join("; ") +
        ", which #{kind} programs are built with; the compiler or linker did not apply the flags Fledge passes"
    end

    # The protections an ELF file has, from what <tt>objdump -p</tt>
    # printed of it (+headers+: a RELRO segment, the STACK segment's flags,
    # the dynamic section's FLAGS, FLAGS_1, and BIND_NOW) and
    # <tt>objdump -T</tt> (+imports+: the functions it imports).
    def self.elf(headers, imports)
      flags = headers[/^\s*FLAGS\s+0x(\h+)/, 1].to_s.to_i(16)
      flags1 = headers[/^\s*FLAGS_1\s+0x(\h+)/, 1].to_s.to_i(16)
      stack = headers[/^\s*STACK off[^\n]*\n\s*filesz\s+\S+\s+memsz\s+\S+\s+flags\s+(\S+)/, 1]
      have = [] # : Array[String]
      have << "PIE" if flags1.anybits?(DF_1_PIE)
      have << "RELRO" if headers.match?(/^\s*RELRO off/)
      have << "BIND_NOW" if headers.match?(/^\s*BIND_NOW\b/) || flags.anybits?(DF_BIND_NOW) || flags1.anybits?(DF_1_NOW)
      have << "non-executable stack" if stack && !stack.include?("x")
      have + symbols(imports)
    end

    # The protections a Mach-O file has, from what <tt>objdump -p</tt>
    # printed of it (+header+: the PIE flag of its Mach header) and
    # <tt>objdump -t</tt> (+listing+; Mach-O names a C symbol with a
    # leading underscore more than ELF does).
    def self.macho(header, listing)
      have = header.match?(/^MH_MAGIC\S*\s.*\bPIE\b/) ? ["PIE"] : []
      have + symbols(listing)
    end

    # The protections a PE file has, from what <tt>llvm-readobj
    # --file-headers</tt> printed of it: the DLLCharacteristics.
    def self.pe(headers)
      headers.scan(/IMAGE_DLL_CHARACTERISTICS_(\w+)/).flatten.map(&:to_s)
    end

    # The stack protector and fortified calls among the symbols a
    # listing names, each symbol the last word of a line.
    def self.symbols(listing)
      names = listing.lines.filter_map { |line| line.split.last }
      have = [] # : Array[String]
      have << "stack protector" if names.any? { |name| name.match?(/\A_?__stack_chk_fail\z/) }
      have << "FORTIFY" if names.any? { |name| name.match?(/\A_?__\w+_chk\z/) }
      have
    end
    private_class_method :symbols

    private def protections(path)
      format = Fledge::Binary.format_of(File.binread(path, 8).to_s) or raise "#{path} is not a compiled program"
      case format
      when :elf then Hardening.elf(tool(:elf, "-p", path), tool(:elf, "-T", path))
      when :macho then Hardening.macho(tool(:macho, "-p", path), tool(:macho, "-t", path))
      when :pe then Hardening.pe(tool(:pe, "--file-headers", path))
      else raise "#{path} is a #{format} file, not a program"
      end
    end

    private def tool(format, *arguments)
      command = @readers.commands.fetch(format) { raise "no tool on this computer reads #{format} files. #{@readers.install}" }
      output, error, status = Open3.capture3(command, *arguments)
      raise "#{command} #{arguments.join(' ')} failed: #{error.strip}" unless status.success?

      output
    end
  end
end
