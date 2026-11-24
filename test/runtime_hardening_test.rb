# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# What RuntimeBuilder::Hardening reads of each format's tool output, and
# the flags each recipe passes (doc/contributors/design/launcher.md,
# "Hardening"). test/integration/runtime_hardening_test.rb reads files
# that a real compiler and linker made.
class RuntimeHardeningTest < Minitest::Test
  # What GNU's objdump -p printed of a program built with every
  # protection: Debian's /usr/bin/true, trimmed to the lines read.
  ELF_HARDENED = <<~OUTPUT
    Program Header:
       STACK off    0x0000000000000000 vaddr 0x0000000000000000 paddr 0x0000000000000000 align 2**4
             filesz 0x0000000000000000 memsz 0x0000000000000000 flags rw-
       RELRO off    0x0000000000005c90 vaddr 0x0000000000005c90 paddr 0x0000000000005c90 align 2**0
             filesz 0x0000000000000370 memsz 0x0000000000000370 flags r--

    Dynamic Section:
      NEEDED               libc.so.6
      FLAGS                0x0000000000000008
      FLAGS_1              0x0000000008000001
  OUTPUT

  ELF_IMPORTS = <<~OUTPUT
    DYNAMIC SYMBOL TABLE:
    0000000000000000      DF *UND*	0000000000000000 (GLIBC_2.4)   __stack_chk_fail
    0000000000000000      DF *UND*	0000000000000000 (GLIBC_2.3.4) __memcpy_chk
    0000000000000000      DF *UND*	0000000000000000 (GLIBC_2.2.5) puts
  OUTPUT

  MACHO_HEADER = <<~OUTPUT
    Mach header
          magic cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags
    MH_MAGIC_64   ARM64        ALL  0x00     EXECUTE    17        976   NOUNDEFS DYLDLINK TWOLEVEL PIE
  OUTPUT

  MACHO_SYMBOLS = <<~OUTPUT
    SYMBOL TABLE:
    0000000000000000         *UND* ___stack_chk_fail
    0000000000000000         *UND* ___stack_chk_guard
    0000000000000000         *UND* ___strcpy_chk
    0000000000000000         *UND* _puts
  OUTPUT

  PE_HEADERS = <<~OUTPUT
    DLLCharacteristics [ (0x4160)
      IMAGE_DLL_CHARACTERISTICS_DYNAMIC_BASE (0x40)
      IMAGE_DLL_CHARACTERISTICS_HIGH_ENTROPY_VA (0x20)
      IMAGE_DLL_CHARACTERISTICS_NX_COMPAT (0x100)
    ]
  OUTPUT

  def elf(headers = ELF_HARDENED, imports = ELF_IMPORTS)
    RuntimeBuilder::Hardening.elf(headers, imports)
  end

  def test_a_hardened_elf_program_has_every_protection
    assert_equal ["PIE", "RELRO", "BIND_NOW", "non-executable stack", "stack protector", "FORTIFY"], elf
  end

  def test_an_elf_program_that_is_not_position_independent_lacks_pie
    refute_includes elf(ELF_HARDENED.sub("0x0000000008000001", "0x0000000000000001")), "PIE"
  end

  def test_an_elf_program_with_no_relro_segment_lacks_relro
    refute_includes elf(ELF_HARDENED.sub(/^\s*RELRO off.*\n.*\n/, "")), "RELRO"
  end

  def test_an_elf_program_whose_symbols_bind_lazily_lacks_bind_now
    lazy = ELF_HARDENED.sub("0x0000000000000008", "0x0000000000000000").sub("0x0000000008000001", "0x0000000008000000")

    refute_includes elf(lazy), "BIND_NOW"
  end

  def test_an_elf_program_with_a_bind_now_entry_has_bind_now
    lazy = ELF_HARDENED.sub("0x0000000000000008", "0x0000000000000000").sub("0x0000000008000001", "0x0000000008000000")

    assert_includes elf("#{lazy}  BIND_NOW             0x0000000000000000\n"), "BIND_NOW"
  end

  def test_an_elf_program_with_an_executable_stack_lacks_a_non_executable_one
    refute_includes elf(ELF_HARDENED.sub("flags rw-", "flags rwx")), "non-executable stack"
  end

  def test_an_elf_program_with_no_stack_header_lacks_a_non_executable_stack
    refute_includes elf(ELF_HARDENED.sub(/^\s*STACK off.*\n.*\n/, "")), "non-executable stack"
  end

  def test_an_elf_program_that_imports_no_canary_check_lacks_a_stack_protector
    refute_includes elf(ELF_HARDENED, ELF_IMPORTS.sub("__stack_chk_fail", "abort")), "stack protector"
  end

  def test_an_elf_program_that_imports_no_checked_function_lacks_fortify
    refute_includes elf(ELF_HARDENED, ELF_IMPORTS.sub("__memcpy_chk", "memcpy")), "FORTIFY"
  end

  def test_the_canary_failure_function_alone_is_not_fortify
    only = "DYNAMIC SYMBOL TABLE:\n0000000000000000      DF *UND*\t0000000000000000 (GLIBC_2.4) __stack_chk_fail\n"

    assert_equal ["stack protector"], RuntimeBuilder::Hardening.elf("", only)
  end

  def test_a_hardened_macho_program_has_every_protection
    assert_equal ["PIE", "stack protector", "FORTIFY"], RuntimeBuilder::Hardening.macho(MACHO_HEADER, MACHO_SYMBOLS)
  end

  # Xcode's linker writes MH_HAS_TLV_DESCRIPTORS after PIE in the
  # launcher, which links Ruby's thread-local variables.
  def test_a_macho_programs_pie_flag_is_found_before_the_flags_after_it
    header = MACHO_HEADER.sub("PIE", "WEAK_DEFINES BINDS_TO_WEAK PIE MH_HAS_TLV_DESCRIPTORS")

    assert_includes RuntimeBuilder::Hardening.macho(header, MACHO_SYMBOLS), "PIE"
  end

  def test_a_macho_program_without_the_pie_flag_lacks_pie
    header = MACHO_HEADER.sub(" PIE", "")

    refute_includes RuntimeBuilder::Hardening.macho(header, MACHO_SYMBOLS), "PIE"
  end

  def test_a_macho_program_that_imports_no_canary_check_or_checked_function_has_neither
    assert_equal ["PIE"], RuntimeBuilder::Hardening.macho(MACHO_HEADER, "SYMBOL TABLE:\n0000000000000000         *UND* _puts\n")
  end

  def test_a_hardened_pe_program_has_every_protection
    assert_equal %w[DYNAMIC_BASE HIGH_ENTROPY_VA NX_COMPAT], RuntimeBuilder::Hardening.pe(PE_HEADERS)
  end

  def test_a_pe_program_with_no_dll_characteristics_has_no_protection
    assert_empty RuntimeBuilder::Hardening.pe("DLLCharacteristics [ (0x0)\n]\n")
  end

  # musl has no fortified calls, and Mach-O no RELRO: a platform asks only
  # for what it has.
  def test_each_kind_requires_only_what_its_platform_provides
    required = RuntimeBuilder::Hardening::REQUIRED

    assert_includes required.fetch(:glibc), "FORTIFY"
    refute_includes required.fetch(:musl), "FORTIFY"
    refute_includes required.fetch(:darwin), "RELRO"
    assert_equal %w[DYNAMIC_BASE HIGH_ENTROPY_VA NX_COMPAT], required.fetch(:windows)
  end

  # Fledge's own object files carry the canary in some and a checked call
  # in others: the program is hardened when its files are, together.
  def test_the_object_files_of_a_program_are_read_together
    Dir.mktmpdir do |dir|
      canary = File.join(dir, "canary.o")
      checked = File.join(dir, "checked.o")
      plain = File.join(dir, "plain.o")
      [canary, checked, plain].each { |path| File.binwrite(path, "\xCF\xFA\xED\xFE".b + ("\0" * 8)) }
      listings = {
        canary => "SYMBOL TABLE:\n0000000000000000         *UND* ___stack_chk_fail\n",
        checked => "SYMBOL TABLE:\n0000000000000000         *UND* ___strcpy_chk\n",
        plain => "SYMBOL TABLE:\n0000000000000000         *UND* _puts\n",
      }
      readers = Object.new
      readers.define_singleton_method(:commands) { { macho: "objdump-stub" } }
      hardening = RuntimeBuilder::Hardening.new(kind: :darwin_objects, readers:)
      hardening.define_singleton_method(:tool) do |_format, flag, path|
        (flag == "-t") ? listings.fetch(path) : MACHO_HEADER
      end

      assert_empty hardening.missing(canary, checked, plain)
      assert_equal ["FORTIFY"], hardening.missing(canary, plain)
      error = assert_raises(RuntimeError) { hardening.check([[canary, plain]]) }
      assert_includes error.message, "#{canary}, #{plain} lacks FORTIFY"
    end
  end

  def test_the_object_files_of_a_mac_program_need_the_canary_and_checked_calls_not_pie
    assert_equal %w[stack\ protector FORTIFY], RuntimeBuilder::Hardening::REQUIRED.fetch(:darwin_objects)
  end

  def test_an_unknown_kind_is_refused
    assert_raises(ArgumentError) { RuntimeBuilder::Hardening.new(kind: :plan9, readers: nil) }
  end

  # Records the commands a recipe would run.
  class Commands
    attr_reader :ran

    def initialize
      @ran = []
    end

    def run(*command, **)
      @ran << command
    end

    def capture(*)
      ""
    end
  end

  # The command that links the program, from a recipe whose compile runs
  # against a stand-in builder; a Linux recipe then fails to find the
  # libxcrypt it never built, after the link.
  def link_command(recipe_class, include_dir)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "prefix", "include", "ruby-4.0.0", include_dir))
      FileUtils.mkdir_p(File.join(dir, "xcrypt", "lib"))
      commands = Commands.new
      def commands.stage = "/nowhere"
      recipe = recipe_class.new(builder: commands, build_dir: dir)
      recipe.instance_variable_set(:@prefix, File.join(dir, "prefix"))
      recipe.instance_variable_set(:@xcrypt, File.join(dir, "xcrypt"))
      sources = [File.join(RuntimeBuilder::Recipe::LAUNCHER, "unix.c")]
      begin
        recipe.compile(File.join(dir, "launcher"), sources, "$ORIGIN/lib")
      rescue RuntimeError => e
        raise unless e.message == "libxcrypt built no libcrypt.so.N"
      end
      commands.ran.find { |command| command.include?("-O2") }
    end
  end

  # A Mac's launcher is compiled to object files with the flags, which
  # Hardening reads, and then linked from them.
  def test_a_darwin_compile_makes_object_files_with_the_flags_and_links_them
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "prefix", "include", "ruby-4.0.0", "arm64-darwin"))
      FileUtils.mkdir_p(File.join(dir, "prefix", "lib"))
      FileUtils.touch(File.join(dir, "prefix", "lib", "libruby.4.0-static.a"))
      commands = Commands.new
      recipe = RuntimeBuilder::Darwin.new(builder: commands, build_dir: dir)
      recipe.instance_variable_set(:@prefix, File.join(dir, "prefix"))
      recipe.compile(File.join(dir, "launcher"), [File.join(RuntimeBuilder::Recipe::LAUNCHER, "unix.c")], "")
      compile = commands.ran.find { |command| command.include?("-c") && command.include?("-O2") }
      link = commands.ran.find { |command| command.include?("-Wl,-pie") }

      RuntimeBuilder::Hardening::COMPILE.fetch(:darwin).each { |flag| assert_includes compile, flag }
      assert_equal [[File.join(dir, "objects", "launcher", "unix.o")]], recipe.objects
      assert_includes link, File.join(dir, "objects", "launcher", "unix.o")
    end
  end

  def test_a_musl_compile_passes_the_flags_hardening_asks_for
    command = link_command(RuntimeBuilder::Musl, "aarch64-linux-musl")

    (RuntimeBuilder::Hardening::COMPILE.fetch(:musl) + RuntimeBuilder::Hardening::LINK.fetch(:musl)).each do |flag|
      assert_includes command, flag
    end
    refute_includes command.join(" "), "_FORTIFY_SOURCE"
  end

  def test_a_glibc_compile_passes_the_flags_hardening_asks_for_with_fortify
    command = link_command(RuntimeBuilder::Linux, "x86_64-linux")

    (RuntimeBuilder::Hardening::COMPILE.fetch(:glibc) + RuntimeBuilder::Hardening::LINK.fetch(:glibc)).each do |flag|
      assert_includes command, flag
    end
    assert_includes command, "-D_FORTIFY_SOURCE=3"
  end
end
