# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/binaries"

# Whether a gem's compiled files would load on the computer an app goes
# to (Fledge::Linkage; ADR 046, and ADR 007): files LLVM's linker made
# (test/support/binaries.rb), read with the tools here.
# test/integration/linkage_mach_o_test.rb has Xcode's clang link the
# Mach-O files dyld's run paths are judged by.
class LinkageTest < Minitest::Test
  def problems(os, files, provided: [])
    TestReaders.need(self, Fledge::Linkage::FORMATS.fetch(os))
    Fledge::Linkage.new(os:, provided:, readers: TestReaders.all).problems("linked 1.0.0", files)
  end

  def test_a_gem_without_compiled_code_has_nothing_to_load
    assert_empty problems("linux", { "lib/plain.rb" => "puts 'ELF'\n", "LICENSE" => "MIT\n" })
  end

  # A compiled file that needs a library neither the operating system,
  # the runtime, nor the gem itself has would not load on the computer
  # the app goes to: a gem compiled against the build machine's own
  # libxml2, say.
  def test_a_library_no_one_ships_keeps_a_gem_from_shipping
    linux = problems("linux", {
"lib/ext.so" => Binaries.elf(needed: %w[libc.so.6 libcrypt.so.2 libxml2.so.2 libown.so]),
"lib/libown.so" => Binaries.elf(needed: ["libm.so.6"]),
}, provided: ["libcrypt.so.2"])
    assert_equal [
"linked 1.0.0's lib/ext.so needs libxml2.so.2, which neither linux, nor Fledge's runtime, nor the gem itself " \
  "provides, so the app could not load it on another computer. Build the gem so that it carries the library, or links " \
  "it statically, or, when every computer the app goes to has it from its Linux distribution, list it in fledge.yml " \
  "as linux: { system_libraries: [libxml2.so.2] }.",
], linux
  end

  # A library the project lists as its gems' to load from the Linux
  # distribution (ADR 030) may be needed, on glibc's Linux and musl's,
  # and every other still keeps a gem from shipping.
  def test_a_library_the_project_lists_as_the_distributions_may_be_needed
    files = {
      "lib/ext.so" => Binaries.elf(needed: %w[libc.so.6 libxml2.so.2]),
      "lib/other.so" => Binaries.elf(needed: %w[libreadline.so.8 libc.so.6]),
    }
    TestReaders.need(self, :elf)
    { "linux" => %w[libxml2.so.2], "linux-musl" => %w[libxml2.so.2 libc.so.6] }.each do |os, system|
      linkage = Fledge::Linkage.new(os:, system:, readers: TestReaders.all)
      found = linkage.problems("linked 1.0.0", files)

      assert_equal 1, found.size, os
      assert_includes found.first, "lib/other.so needs libreadline.so.8", os
      assert_includes found.first, "linux: { system_libraries: [libreadline.so.8] }", os
      assert_empty linkage.unused, os
    end
  end

  # A library listed that no gem's compiled file needs from the system,
  # because none needs it, or every distribution, the runtime, or the gem
  # already provides it, is refused, so the list says only what is true
  # and a .deb depends on nothing more.
  def test_a_listed_library_no_gem_needs_from_the_system_is_refused
    TestReaders.need(self, :elf)
    linkage = Fledge::Linkage.new(os: "linux", provided: ["libcrypt.so.2"], system: %w[libxml2.so.2 libc.so.6 libcrypt.so.2 libown.so libgtk-3.so.0],
      readers: TestReaders.all)
    assert_empty linkage.problems("linked 1.0.0", {
      "lib/ext.so" => Binaries.elf(needed: %w[libc.so.6 libcrypt.so.2 libxml2.so.2 libown.so]),
      "lib/libown.so" => Binaries.elf(needed: ["libm.so.6"]),
    })
    assert_empty linkage.problems("plain 1.0.0", { "lib/plain.rb" => "" })

    assert_equal %w[libc.so.6 libcrypt.so.2 libown.so libgtk-3.so.0].map { |library|
      "fledge.yml's linux: system_libraries lists #{library}, which none of the gems' compiled files needs beyond what every " \
        "Linux distribution, Fledge's runtime, and the gems themselves provide. Remove it."
    }, linkage.unused
  end

  def test_a_dylib_no_one_ships_keeps_a_gem_from_shipping_on_macos
    macos = problems("darwin", {
"lib/ext.bundle" => Binaries.macho(needed: [
  "/usr/lib/libSystem.B.dylib",
  "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation",
  "@loader_path/../ports/libpq.5.dylib",
  "/opt/homebrew/opt/libxml2/lib/libxml2.2.dylib",
]),
"ports/libpq.5.dylib" => Binaries.macho(needed: ["/usr/lib/libz.1.dylib"]),
})
    assert_equal 1, macos.size
    assert_includes macos.first, "needs /opt/homebrew/opt/libxml2/lib/libxml2.2.dylib, which neither darwin"
  end

  def test_a_dll_no_one_ships_keeps_a_gem_from_shipping_on_windows
    windows = problems("windows", {
"lib/ext.so" => Binaries.pe(needed: %w[
  x64-ucrt-ruby400.dll
  KERNEL32.dll
  api-ms-win-crt-heap-l1-1-0.dll
  libxml2-16.dll
]),
}, provided: ["x64-ucrt-ruby400.dll"])
    assert_equal 1, windows.size
    assert_includes windows.first, "needs libxml2-16.dll"
  end

  # A game's engine, its window and input library, and its audio library
  # link DLLs that are in System32 on every Windows a Fledge app runs on,
  # x64 and ARM64, as a 2D game gem's precompiled Windows build links
  # them: the Desktop Window Manager's, the input method editor's, the
  # device installer's, the multimedia scheduler's, and Direct3D's,
  # DirectInput's, DirectSound's, and the HID class driver's.
  def test_the_dlls_every_windows_has_for_windows_input_and_sound_need_no_shipping
    windows = problems("windows", {
"lib/game/native.so" => Binaries.pe(needed: %w[
  x64-ucrt-ruby400.dll
  dwmapi.dll
  IMM32.dll
  SETUPAPI.dll
  cfgmgr32.dll
  HID.dll
  d3d9.dll
  d3d11.dll
  dxgi.dll
  DINPUT8.dll
  DSOUND.dll
  OpenAL32.dll
]),
"lib/game/libraries/OpenAL32.dll" => Binaries.pe(needed: %w[KERNEL32.dll AVRT.dll ole32.dll WINMM.dll]),
}, provided: ["x64-ucrt-ruby400.dll"])
    assert_empty windows
  end

  def test_a_file_for_another_ruby_is_never_loaded_and_never_judged
    assert_empty problems("windows", { "lib/ext/3.4/ext.so" => Binaries.pe(needed: %w[x64-ucrt-ruby340.dll libother.dll]) },
      provided: ["x64-ucrt-ruby400.dll"])
  end

  def test_manylinux_2_39_lets_a_linux_binary_assume_what_every_distribution_has
    assert_empty problems("linux", { "lib/ext.so" => Binaries.elf(needed: %w[libz.so.1 libstdc++.so.6 ld-linux-x86-64.so.2]) })
  end

  # What a library compiled in is, or what license it is under, is not
  # a question of whether the app loads: a file with GNU libiconv's code
  # in it, as nokogiri's precompiled macOS and Windows builds have, loads
  # like any other (ADR 007).
  def test_code_compiled_in_is_not_judged
    iconv = "UCS-4-INTERNAL MULELAO-1 GNU MP: Cannot allocate memory yescrypt-ROMhash"

    assert_empty problems("linux", { "lib/ext.so" => Binaries.elf(needed: ["libc.so.6"], payload: iconv) })
  end

  # A loader loads only its own system's format, so a Linux gem's copy of
  # a Windows DLL, say, is never loaded and never judged.
  def test_a_file_for_another_systems_loader_is_never_judged
    assert_empty problems("linux", { "vendor/win/ext.dll" => Binaries.pe(needed: %w[libgmp-10.dll KERNEL32.dll]) })
  end
end
