# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/binaries"

# What Fledge::Binary reads from compiled files with the system's tools
# (Fledge::Binary::Readers): files LLVM's compiler and linker made
# (test/support/binaries.rb), read as each tool reads any compiler's.
class BinaryTest < Minitest::Test
  def parse(files)
    Fledge::Binary.parse(files, readers: TestReaders.all)
  end

  def one(bytes)
    parse({ "file" => bytes })["file"]
  end

  def test_reads_the_libraries_an_elf_file_needs_and_the_oldest_glibc_it_runs_on
    TestReaders.need(self, :elf)
    binary = one(Binaries.elf(needed: %w[libc.so.6], versions: %w[GLIBC_2.2.5 GLIBC_2.34 GLIBC_2.17]))

    assert_equal [:elf, %w[libc.so.6], "2.34"], [binary.format, binary.needed, binary.glibc_minimum]
    assert_equal %w[libcrypt.so.2 libm.so.6 libc.so.6 ld-linux-x86-64.so.2],
      one(Binaries.elf(needed: %w[libcrypt.so.2 libm.so.6 libc.so.6 ld-linux-x86-64.so.2])).needed
    assert_nil one(Binaries.elf(needed: %w[libc.so.6])).glibc_minimum
  end

  def test_reads_the_dylibs_a_mach_o_file_loads_and_the_oldest_macos_it_runs_on
    TestReaders.need(self, :macho)
    binary = one(Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib @rpath/libffi.dylib]))

    assert_equal [:macho, %w[/usr/lib/libSystem.B.dylib @rpath/libffi.dylib], "14.0"], [binary.format, binary.needed, binary.macos_minimum]
    assert_equal "27.1", one(Binaries.macho(minos: "27.1")).macos_minimum
  end

  # The name a library gives itself, which a loader matches a later need
  # against once the library is loaded: an ELF file's SONAME, a Mach-O
  # dylib's install name (LC_ID_DYLIB). A file with none, or a bundle,
  # has none.
  def test_reads_the_name_a_library_gives_itself
    TestReaders.need(self, :elf, :macho)

    assert_equal "libraylib.so.600", one(Binaries.elf(needed: %w[libc.so.6], soname: "libraylib.so.600")).soname
    assert_nil one(Binaries.elf(needed: %w[libc.so.6])).soname
    assert_equal "@rpath/libraylib.600.dylib",
      one(Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib], install_name: "@rpath/libraylib.600.dylib")).soname
    assert_nil one(Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib])).soname
  end

  # The processor each file's code is for, by Fledge::Platform#cpu's
  # names, whichever processor the computer reading it has: an ELF
  # file's from its header, which GNU's objdump names only for its own
  # computer's processors, and a Mach-O or PE file's as LLVM's tools
  # name it.
  def test_reads_the_processor_an_elf_or_mach_o_files_code_is_for
    TestReaders.need(self, :elf, :macho)
    found = {
      Binaries.elf(needed: %w[libc.so.6]) => ["x86_64"],
      Binaries.elf(needed: %w[libc.so.6 libGLX.so.0], cpu: "aarch64") => ["aarch64"],
      Binaries.elf(needed: %w[libc.so.6 libGLX.so.0], cpu: "i386") => ["i386"],
      Binaries.elf(needed: %w[libc.so.6 libGLX.so.0], cpu: "arm") => ["arm"],
      Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib]) => ["aarch64"],
      Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib /usr/local/opt/libxml2/lib/libxml2.2.dylib], cpu: "x86_64") => ["x86_64"],
    }

    assert_equal found.values, found.keys.map { |bytes| one(bytes).architectures }
  end

  def test_reads_the_processor_a_pe_files_code_is_for
    TestReaders.need(self, :pe)

    assert_equal [["x86_64"], ["aarch64"]],
      [Binaries.pe(needed: %w[KERNEL32.dll]), Binaries.pe(needed: %w[KERNEL32.dll libxml2-16.dll], cpu: "aarch64")].map { |bytes| one(bytes).architectures }
  end

  # A file built for iOS names no macOS to run on.
  def test_a_mach_o_file_for_another_platform_says_no_macos
    TestReaders.need(self, :macho)

    assert_nil one(Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib], platform: "ios")).macos_minimum
  end

  # The import table and the delay import table, which only
  # llvm-readobj prints, and the manifest's dependent assemblies.
  def test_reads_the_dlls_a_pe_file_imports_and_delay_loads
    TestReaders.need(self, :pe)
    manifest = '<dependentAssembly><assemblyIdentity type="win32" name="ruby_builtin_dlls" /></dependentAssembly>'
    binary = one(Binaries.pe(needed: %w[libgmp-10.dll KERNEL32.dll], payload: manifest))

    assert_equal [:pe, %w[KERNEL32.dll libgmp-10.dll], ["ruby_builtin_dlls"]], [binary.format, binary.needed.sort, binary.assemblies]
    assert_equal %w[KERNEL32.dll USER32.dll], one(Binaries.pe(needed: %w[KERNEL32.dll], delayed: %w[USER32.dll])).needed
  end

  def test_reads_whether_a_windows_program_is_a_console_or_a_gui_program
    TestReaders.need(self, :pe)

    assert_equal 3, one(Binaries.pe(needed: %w[KERNEL32.dll], program: "console")).subsystem
    assert_equal 2, one(Binaries.pe(needed: %w[KERNEL32.dll], program: "windows")).subsystem
  end

  # A file that begins as compiled code does but that the tool does not
  # recognize, a Java class or a text that starts with MZ, holds none,
  # and the files after it are still read. An archive is code that links
  # nothing, which no tool need read.
  def test_only_what_the_tool_recognizes_is_compiled_code
    TestReaders.need(self, :elf, :macho, :pe)
    found = parse({
      "Main.class" => [0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 65].pack("C*"),
      "notes.txt" => "MZ is where the notes begin\n",
      "a.bundle" => Binaries.macho(needed: %w[/usr/lib/libz.1.dylib]),
      "libruby.a" => "!<arch>\nfoo.o/",
      "b.so" => Binaries.elf(needed: %w[libm.so.6]),
      "plain.rb" => "puts 'ELF'\n",
    })

    assert_equal %w[a.bundle b.so libruby.a], found.keys.sort
    assert_equal [:archive, []], [found.fetch("libruby.a").format, found.fetch("libruby.a").needed]
    assert_equal %w[libm.so.6], found.fetch("b.so").needed
  end

  # The license audit reads with LLVM's tools (Fledge::Binary::Readers.llvm)
  # what fledge build reads with this computer's: both must say the same.
  def test_llvms_tools_read_every_file_as_this_computers_own_do
    llvm = ENV.fetch("FLEDGE_LLVM", "")
    skip "FLEDGE_LLVM names no LLVM bin folder" if llvm.empty?

    files = Binaries::CATALOG.to_h { |spec| [Binaries.name(spec), Binaries.file(spec, "")] }
    own = Fledge::Binary::Readers.local(TestReaders.os, readobj: TestReaders.readobj)
    mine = files.select { |_, bytes| own.reads?(Fledge::Binary.format_of(bytes)) }

    assert_equal Fledge::Binary.parse(mine, readers: own), Fledge::Binary.parse(mine, readers: Fledge::Binary::Readers.llvm(llvm))
    assert_equal files.keys.sort, Fledge::Binary.parse(files, readers: Fledge::Binary::Readers.llvm(llvm)).keys.sort
  end

  def test_a_format_no_tool_here_reads_is_an_error_that_says_what_to_install
    readers = Fledge::Binary::Readers.local("windows")

    error = assert_raises(Fledge::Error) { Fledge::Binary.parse({ "x.dll" => Binaries.pe(needed: %w[KERNEL32.dll]) }, readers:) }
    assert_includes error.message, "no tool on this computer reads pe files"
    assert_includes error.message, "tools/llvm-readobj.exe"
  end

  def test_a_tool_that_cannot_run_says_what_to_install
    readers = Fledge::Binary::Readers.new(commands: { elf: "/nonexistent/objdump" }, install: "Install binutils.")

    error = assert_raises(Fledge::Error) { Fledge::Binary.parse({ "x.so" => Binaries.elf(needed: %w[libc.so.6]) }, readers:) }
    assert_includes error.message, "Install binutils."
  end
end
