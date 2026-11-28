# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "tmpdir"
require_relative "error"

module Fledge
  # What a compiled file links and what system it was built for, as the
  # system's own tools read it from the file.
  #
  # Fledge copies compiled code into every app: the runtime's, and the
  # native gems an app's Gemfile.lock locks. What a file links decides
  # whether it loads on the computer the app goes to, and, for Fledge's
  # own runtime, what a license asks of the app's developer, since an LGPL
  # library may ship in a runtime only as a separate shared library that
  # another file loads, never compiled into it. The oldest macOS or glibc a
  # file names decides the oldest system it loads on.
  #
  # Fledge reads none of these formats itself. An objdump reads
  # ELF and Mach-O (<tt>objdump -p</tt>: an ELF file's dynamic section and
  # version references, a Mach-O file's load commands), GNU's on Linux and
  # LLVM's, which Xcode's command line tools install as objdump, on a Mac;
  # LLVM's llvm-readobj reads PE (<tt>--coff-imports</tt>, which unlike
  # objdump names the DLLs a file delay-loads, and
  # <tt>--file-headers</tt>). Which tool reads which format on a computer
  # is Fledge::Binary::Readers. This class only picks out the files that
  # begin as compiled code does, by the bytes each format starts with, as
  # file(1) does, hands them to the tool, and keeps what the tool printed,
  # with an ELF file's processor, which it reads from the file's header,
  # as file(1) does too (#architectures).
  # A file the tool does not recognize holds no code. A static archive
  # (ar) is code that links nothing, since what matters about it is that
  # its code would be copied into whatever links it; no tool is asked.
  #
  # Use it to audit a runtime, to check that an app's native
  # gems will load (Fledge::Linkage), and to check a compiled gem against
  # its platform's oldest system (Fledge::NativeBuild).
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   readers = Fledge::Binary::Readers.local("linux")
  #   binary = Fledge::Binary.read(["lib/sqlite3/4.0/sqlite3_native.so"], readers:).values.first
  #   binary.format        # => :elf
  #   binary.needed        # => ["libm.so.6", "libz.so.1", "libdl.so.2", "libpthread.so.0", "libc.so.6"]
  #   binary.glibc_minimum # => "2.29"
  #
  #   Fledge::Binary.format_of("puts 'hello'\n") # => nil
  #--
  # SPDX-SnippetEnd
  #++
  class Binary < Data.define(:format, :needed, :rpaths, :assemblies, :macos_minimum, :glibc_minimum, :subsystem, :soname, :architectures)
    ##
    # :attr_reader: format
    # The file's format: <tt>:elf</tt>, <tt>:macho</tt>, <tt>:pe</tt>, or
    # <tt>:archive</tt>.

    ##
    # :attr_reader: needed
    # The shared libraries the file needs, as the file names them, once
    # each.

    ##
    # :attr_reader: rpaths
    # The run paths a Mach-O file's LC_RPATH commands name, in order,
    # where dyld looks for a library the file names as
    # <tt>@rpath/NAME</tt>; empty for other formats.

    ##
    # :attr_reader: assemblies
    # The side-by-side assemblies a PE's embedded manifest names.

    ##
    # :attr_reader: macos_minimum
    # The oldest macOS a Mach-O file says it runs on, as
    # <tt>MAJOR.MINOR</tt>, or +nil+. A compiler writes the deployment
    # target it was given, or else the macOS it runs on.

    ##
    # :attr_reader: glibc_minimum
    # The oldest glibc an ELF file runs on: the newest
    # <tt>GLIBC_X.Y</tt> symbol version it needs, as auditwheel reads it
    # to judge a wheel's manylinux tag, or +nil+.

    ##
    # :attr_reader: subsystem
    # A PE program's Subsystem: 2 for a GUI program, 3 for a console
    # one; +nil+ for other formats.

    ##
    # :attr_reader: soname
    # The name a shared library gives itself, which its system's loader
    # matches a later need against once the library is loaded: an ELF
    # file's DT_SONAME, or a Mach-O dylib's install name (LC_ID_DYLIB);
    # +nil+ for a file that gives none, and for PE, whose loader matches
    # a loaded DLL by its file name.

    ##
    # :attr_reader: architectures
    # The processors the file holds code for, once each, by the names
    # Fledge::Platform#cpu gives them (<tt>x86_64</tt>,
    # <tt>aarch64</tt>), and <tt>i386</tt> or <tt>arm</tt>, or by the
    # tool's own name for one Fledge does not name: one for most files,
    # one for each slice of a universal Mach-O file, and none for a static
    # archive. A file's code runs only in a process of one of them.

    # ELF's e_machine values for the processors #architectures names (the
    # gABI's EM_386, EM_ARM, EM_X86_64, and EM_AARCH64).
    ELF_MACHINES = { 3 => "i386", 40 => "arm", 62 => "x86_64", 183 => "aarch64" }.freeze

    # The bytes each format's files begin with: ELF's, a static
    # archive's, a 64-bit and a 32-bit little-endian Mach-O file's and a
    # universal one's (which a Java class file shares, and which the tool
    # then refuses), and DOS's MZ, which begins every PE file.
    MAGICS = {
      elf: ["\x7FELF".b],
      archive: ["!<arch>\n".b],
      macho: [[0xCF, 0xFA, 0xED, 0xFE], [0xCE, 0xFA, 0xED, 0xFE], [0xCA, 0xFE, 0xBA, 0xBE]].map { |bytes| bytes.pack("C*") },
      pe: ["MZ".b],
    }.freeze

    # A PE's embedded manifest naming a dependent assembly, which the
    # loader must find beside the file.
    ASSEMBLY = /<dependentAssembly>\s*<assemblyIdentity[^>]*name="([^"]+)"/m

    # The format +bytes+ (a file's first bytes will do) begin as, or nil.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Binary.format_of("!<arch>\nfoo.o/") # => :archive
    #--
    # SPDX-SnippetEnd
    #++
    def self.format_of(bytes)
      bytes = bytes.b
      MAGICS.find { |_, magics| magics.any? { |magic| bytes.start_with?(magic) } }&.first
    end

    # The Binary of each file among +paths+ that holds compiled code, by
    # its path, as +readers+ (Fledge::Binary::Readers) read them. Raises
    # Fledge::Error when no reader reads a file's format, or a reader
    # fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Binary.read(Dir["bin/*"], readers: Fledge::Binary::Readers.local("darwin")).keys # => ["bin/ruby"]
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(paths, readers:)
      formats = {} # : Hash[String, Symbol]
      paths.each do |path|
        next if File.symlink?(path) || !File.file?(path)

        format = format_of(File.binread(path, 8).to_s)
        formats[path] = format if format
      end
      binaries = formats.select { |_, format| format == :archive }.transform_values { archive }
      formats.reject { |_, format| format == :archive }.keys.group_by { |path| formats.fetch(path) }.each do |format, found|
        readers.read(format, found).each { |path, binary| binaries[path] = with_machine(path, with_assemblies(path, binary)) }
      end
      paths.filter_map { |path| (binary = binaries[path]) && [path, binary] }.to_h
    end

    # The Binary of each of +files+ (names, and their bytes) that holds
    # compiled code, by its name, as #read reads them from a file each.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   files = { "lib/ext.so" => File.binread("ext.so"), "lib/ext.rb" => "require 'ext.so'\n" }
    #   Fledge::Binary.parse(files, readers: Fledge::Binary::Readers.local("linux")).keys # => ["lib/ext.so"]
    #--
    # SPDX-SnippetEnd
    #++
    def self.parse(files, readers:)
      compiled = files.select { |_, bytes| format_of(bytes.byteslice(0, 8).to_s) }
      return {} if compiled.empty?

      Dir.mktmpdir("fledge-binary") do |dir|
        names = compiled.keys.each_with_index.to_h { |name, index| [File.join(dir, index.to_s), name] }
        names.each { |path, name| File.binwrite(path, compiled.fetch(name)) }
        read(names.keys, readers:).transform_keys { |path| names.fetch(path) }
      end
    end

    # Whether a process on +cpu+ (Fledge::Platform#cpu) could load the
    # file: when it holds code for that processor, among others in a
    # universal Mach-O file, or when its #architectures could not be
    # read, so that no check lets a file off for what its reader did not
    # say.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   binary.architectures            # => ["aarch64"]
    #   binary.for?("x86_64")           # => false
    #--
    # SPDX-SnippetEnd
    #++
    def for?(cpu)
      architectures.empty? || architectures.include?(cpu)
    end

    private_class_method def self.archive # :nodoc:
      new(format: :archive, needed: [], rpaths: [], assemblies: [], macos_minimum: nil, glibc_minimum: nil, subsystem: nil, soname: nil,
        architectures: [])
    end

    # +binary+, with the processor the ELF file at +path+ is for, as its
    # header's e_machine says (at byte 18, in the byte order byte 5
    # gives, in the gABI's "ELF Header"), as file(1) reads it: GNU's
    # objdump names a file's processor only among those it was built for,
    # and calls an aarch64 file on an x86-64 computer "elf64-little", and
    # readelf, which names every one, would be a second tool to run.
    private_class_method def self.with_machine(path, binary) # :nodoc:
      return binary unless binary.format == :elf

      header = File.binread(path, 20).to_s
      return binary if header.bytesize < 20

      machine = header.byteslice(18, 2).to_s.unpack1((header.getbyte(5) == 2) ? "n" : "v")
      binary.with(architectures: [ELF_MACHINES.fetch(machine) { "e_machine #{machine}" }])
    end

    # +binary+, with the assemblies the manifest in the PE file at +path+
    # names, which no tool prints: a manifest is XML that a resource
    # holds, so its text is in the file's bytes, as strings(1) finds it.
    private_class_method def self.with_assemblies(path, binary) # :nodoc:
      return binary unless binary.format == :pe

      binary.with(assemblies: File.binread(path).scan(ASSEMBLY).flatten.map(&:to_s).uniq)
    end
  end
end

require_relative "binary/objdump"
require_relative "binary/readobj"
require_relative "binary/readers"
