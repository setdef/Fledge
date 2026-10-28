# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"

# Whether a gem's compiled files would load on the computer an app goes
# to (Fledge::Linkage; ADR 006, section 8, and ADR 007): binaries written
# byte for byte as each format specifies (test/support/binaries.rb).
class LinkageTest < Minitest::Test
  def problems(os, files, provided: [])
    Fledge::Linkage.new(os:, provided:).problems("linked 1.0.0", files)
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
  "it statically.",
], linux

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

    assert_empty problems("windows", { "lib/ext.so" => Binaries.pe(needed: ["KERNEL32.dll"], payload: iconv) })
    assert_empty problems("linux", { "lib/ext.so" => Binaries.elf(needed: ["libc.so.6"], payload: iconv) })
  end
end
