# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
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
  # another file loads, never compiled into it (decision 8 in
  # <tt>doc/contributors/decisions.md</tt>). The oldest macOS or glibc a
  # file names decides the oldest system it loads on.
  #
  # Fledge reads none of these formats itself (ADR 013). An objdump reads
  # ELF and Mach-O (<tt>objdump -p</tt>: an ELF file's dynamic section and
  # version references, a Mach-O file's load commands), GNU's on Linux and
  # LLVM's, which Xcode's command line tools install as objdump, on a Mac;
  # LLVM's llvm-readobj reads PE (<tt>--coff-imports</tt>, which unlike
  # objdump names the DLLs a file delay-loads, and
  # <tt>--file-headers</tt>). Which tool reads which format on a computer
  # is Fledge::Binary::Readers. This class only picks out the files that
  # begin as compiled code does, by the bytes each format starts with, as
  # file(1) does, hands them to the tool, and keeps what the tool printed.
  # A file the tool does not recognize holds no code. A static archive
  # (ar) is code that links nothing, since what matters about it is that
  # its code would be copied into whatever links it; no tool is asked.
  #
  # Use it to audit a runtime (ADR 004), to check that an app's native
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
  class Binary < Data.define(:format, :needed, :rpaths, :assemblies, :macos_minimum, :glibc_minimum, :subsystem)
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
        readers.read(format, found).each { |path, binary| binaries[path] = with_assemblies(path, binary) }
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

    private_class_method def self.archive # :nodoc:
      new(format: :archive, needed: [], rpaths: [], assemblies: [], macos_minimum: nil, glibc_minimum: nil, subsystem: nil)
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
