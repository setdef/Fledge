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
  # native gems an app's Gemfile.lock locks. What a file links decides
  # whether it loads on the computer the app goes to, and, for Fledge's
  # own runtime, what a license asks of the app's developer, since an LGPL
  # library may ship in a runtime only as a separate shared library that
  # another file loads, never compiled into it (decision 8 in
  # <tt>doc/contributors/decisions.md</tt>). Tools that answer the
  # question (readelf, otool, objdump) each read one format, on one
  # operating system.
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
  # Use it to audit a runtime (ADR 004), or to check that an app's native
  # gems will load (Fledge::Linkage).
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
    MACHO_MAGICS = [[0xCF, 0xFA, 0xED, 0xFE].pack("C*"), [0xCE, 0xFA, 0xED, 0xFE].pack("C*")].freeze
    # The first bytes of a universal (fat) Mach-O file.
    FAT_MAGIC = [0xCA, 0xFE, 0xBA, 0xBE].pack("C*")

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
      if bytes.start_with?(ELF_MAGIC) then from(:elf, Elf.new(bytes).links)
      elsif MACHO_MAGICS.any? { |magic| bytes.start_with?(magic) } || MachO.fat?(bytes) then from(:macho, MachO.new(bytes).links)
      elsif bytes.start_with?("MZ") && Pe.pe?(bytes) then pe(Pe.new(bytes))
      elsif bytes.start_with?(AR_MAGIC) then new(format: :archive, needed: [], rpaths: [], assemblies: [])
      end
    end

    # The oldest macOS the Mach-O file +bytes+ says it runs on, as
    # <tt>MAJOR.MINOR</tt>, or +nil+ when it is not a Mach-O file or says
    # none. A compiler writes the deployment target it was given, or else
    # the macOS it runs on, so a gem compiled on a new Mac may refuse to
    # load on an older one the runtime supports.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Binary.macos_minimum(File.binread("redcarpet.bundle")) # => "14.0"
    #--
    # SPDX-SnippetEnd
    #++
    def self.macos_minimum(bytes)
      reader = MachO.new(bytes.b)
      reader.minimum if reader.macho?
    end

    # The oldest glibc the ELF file +bytes+ runs on: the newest
    # <tt>GLIBC_X.Y</tt> symbol version it needs, as auditwheel reads it to
    # judge a wheel's manylinux tag, or +nil+ when it is not an ELF file or
    # needs none. A compiler links against the glibc it runs on, so a gem
    # compiled on a newer Linux may refuse to load on an older one the
    # runtime supports.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Binary.glibc_minimum(File.binread("redcarpet.so")) # => "2.34"
    #--
    # SPDX-SnippetEnd
    #++
    def self.glibc_minimum(bytes)
      bytes = bytes.b
      Elf.new(bytes).glibc_minimum if bytes.start_with?(ELF_MAGIC)
    end

    private_class_method def self.from(format, links) # :nodoc:
      needed, rpaths = links
      new(format:, needed:, rpaths:, assemblies: [])
    end

    private_class_method def self.pe(reader) # :nodoc:
      new(format: :pe, needed: reader.needed, rpaths: [], assemblies: reader.assemblies)
    end
  end
end

require_relative "binary/reader"
require_relative "binary/elf"
require_relative "binary/mach_o"
require_relative "binary/pe"
