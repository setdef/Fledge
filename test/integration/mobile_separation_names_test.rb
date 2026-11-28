# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require_relative "../support/android"
require_relative "../support/ios"

# How each phone's tools read the names an extension's object defines, from an
# object that also carries LLVM bitcode in a section LLVM's nm reads names from
# in place of the symbol table: on iOS __LLVM,__bitcode, which Rust's standard
# library carries, and where an nm older than Rust's LLVM stops; on Android
# .llvm.lto, a fat LTO object's, since that nm reads no other ELF section,
# Rust's .llvmbc among them. Each test's object carries bitcode no LLVM reads in
# that section, and shows first that its nm, reading it as it would by
# default, stops; the iOS tests also read an object of Rust's own
# standard library. Without
# Xcode, the NDK, or Rust's iOS targets they skip, and fail instead
# where FLEDGE_REQUIRE_IOS or FLEDGE_REQUIRE_ANDROID is set.
class MobileSeparationNamesTest < Minitest::Test
  include AndroidRequired
  include IOSRequired

  Tools = Fledge::MobileExtensions::Separation::Tools
  Target = Fledge::MobileExtensions::Target

  # A function of each visibility an extension's names have, and a
  # section of bytes that begin as LLVM bitcode does and that no LLVM
  # reads; SECTION is the section's name and flags.
  SOURCE = <<~C
    int default_name(void) { return 1; }
    __attribute__((visibility("hidden"))) int hidden_name(void) { return 2; }
    static int local_name(void) { return 3; }
    int calls_local(void) { return local_name(); }
    __asm__(".section SECTION\\n.byte 0x42,0x43,0xc0,0xde,0x35,0x14,0x00,0x00,0x05,0x00,0x00,0x00,0x62,0x0c,0x30,0x24\\n.text\\n");
  C

  def setup
    @dir = Fledge::LongPath.of(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_ios_names_are_read_from_the_symbol_table_of_an_object_with_bitcode_no_llvm_reads
    tools = apple
    object = compile("__LLVM,__bitcode", "xcrun", "--sdk", "iphonesimulator", "clang", "-target", "arm64-apple-ios15.0-simulator")
    assert_unreadable("xcrun", "nm", "-m", object)

    assert_equal %w[calls_local default_name hidden_name], tools.names(object).sort
  end

  def test_ios_names_are_read_from_an_object_of_rusts_standard_library
    tools = apple
    object = rust_object("aarch64-apple-ios-sim")
    sections, = Open3.capture2e("xcrun", "otool", "-l", object)
    assert_match(/sectname __bitcode\s+segname __LLVM/, sections, "Rust's core library carries bitcode")

    assert_operator tools.names(object).size, :>, 100
  end

  def test_android_names_are_read_from_the_symbol_table_of_an_object_with_bitcode_no_llvm_reads
    bin = ndk_bin
    object = compile('.llvm.lto,\"e\"', File.join(bin, "clang"), "--target=aarch64-linux-android24")
    assert_unreadable(File.join(bin, "llvm-nm"), "--defined-only", "--extern-only", object)

    names = Tools::Android.new(target("android-arm64-v8a", "arm64-v8a", "FLEDGE_AR" => File.join(bin, "llvm-ar")), nil).names(object)
    assert_equal %w[calls_local default_name hidden_name], names.sort
  end

  # Compiles SOURCE, its bitcode in the section +section+, with
  # +compiler+, a command, into an object, whose path it returns.
  private def compile(section, *compiler)
    source = File.join(@dir, "names.c")
    object = File.join(@dir, "names.o")
    File.write(source, SOURCE.sub("SECTION") { section })
    out, status = Open3.capture2e(*compiler, "-c", source, "-o", object)
    assert_predicate status, :success?, "#{compiler.join(' ')} compiled #{source}:\n#{out}"
    object
  end

  # Asserts that +command+, an nm reading names from LLVM bitcode where
  # an object has it, fails: the premise of the test.
  private def assert_unreadable(*command)
    out, status = Open3.capture2e(*command)
    refute_predicate status, :success?, "#{command.join(' ')} reads the bitcode no LLVM reads, so this test shows nothing:\n#{out}"
  end

  private def apple
    ios_missing("Xcode's tools are on a Mac only") unless Fledge::Platform.local.name == "arm64-darwin"
    Tools::Apple.new(target("ios-arm64-simulator", nil), nil)
  end

  private def target(name, abi, environment = {})
    Target.new(name:, root: @dir, arch_dir: @dir, libdir: @dir, environment:, abi:)
  end

  # An object of Rust's core library for +triple+, as a Rust extension's
  # static library carries it.
  private def rust_object(triple)
    sysroot, status = Open3.capture2e("rustc", "--print", "sysroot")
    ios_missing("no rustc: install mise.toml's Rust (tasks/setup.rb)") unless status.success?
    rlib = Dir.glob(File.join(sysroot.strip, "lib", "rustlib", triple, "lib", "libcore-*.rlib")).first
    ios_missing("Rust has no #{triple} target: rustup target add #{triple} (tasks/setup.rb)") unless rlib
    member = IO.popen(["ar", "t", rlib], &:readlines).map(&:strip).find { |name| name.end_with?(".o") } or flunk "#{rlib} holds no object"
    assert system("ar", "x", rlib, member, chdir: @dir), "ar extracted #{member} from #{rlib}"
    File.join(@dir, member)
  end

  private def ndk_bin
    Fledge::MobileExtensions::NDK.find(ENV, host: Fledge::Platform.local).bin
  rescue Fledge::Error => e
    android_missing(e.message)
  end
end
