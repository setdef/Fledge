# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"
require "open3"

# Whether a gem's compiled files would load on the computer an app goes
# to (Fledge::Linkage; ADR 006, section 8, and ADR 007): files LLVM's
# linker made (test/support/binaries.rb), read with the tools here.
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

  # dyld finds an @rpath library only through the run paths of the file
  # that needs it and of the files that loaded that one. A run path into
  # Homebrew's folder reaches nothing the app carries, so a gem whose
  # library sits in a folder no run path names would load only on a Mac
  # with Homebrew.
  def test_an_rpath_library_no_run_path_reaches_keeps_a_gem_from_shipping_on_macos
    files = mach_o do |build|
      build.dylib("vendor/libfoo.dylib", install_name: "@rpath/libfoo.dylib")
      build.bundle("lib/ext.bundle", links: ["vendor/libfoo.dylib"], rpaths: ["/opt/homebrew/lib"])
    end

    assert_equal [
      "linked 1.0.0's lib/ext.bundle needs @rpath/libfoo.dylib, which the gem carries at vendor/libfoo.dylib, but none of the " \
        "run paths dyld would search for it (/opt/homebrew/lib) leads there, so the app could not load it on another computer. " \
        "Give the file a run path that does, such as @loader_path/../vendor (install_name_tool -add_rpath), or build the gem so " \
        "that it has one.",
    ], problems("darwin", files)
  end

  def test_an_rpath_library_with_no_run_path_at_all_says_so
    files = mach_o do |build|
      build.dylib("lib/libfoo.dylib", install_name: "@rpath/libfoo.dylib")
      build.bundle("lib/ext.bundle", links: ["lib/libfoo.dylib"], rpaths: [])
    end

    assert_includes problems("darwin", files).first, "but none of the run paths dyld would search for it (it has none) leads there"
  end

  # A run path outside the app reaches nothing, but costs nothing either
  # when another run path reaches the library: here a framework in a
  # folder beside the bundle, which dyld finds at @loader_path/frameworks.
  def test_a_run_path_that_reaches_the_library_lets_it_ship_beside_one_that_does_not
    files = mach_o do |build|
      build.dylib("lib/frameworks/Foo.framework/Versions/A/Foo", install_name: "@rpath/Foo.framework/Versions/A/Foo")
      build.bundle("lib/ext.bundle", links: ["lib/frameworks/Foo.framework/Versions/A/Foo"],
        rpaths: ["/Library/Frameworks", "@loader_path/frameworks"])
    end

    assert_empty problems("darwin", files)
  end

  # A library a gem's bundle loads finds its own @rpath libraries through
  # the bundle's run paths too, as dyld searches the run paths of every
  # file on the way from the program to it.
  def test_a_library_finds_its_rpath_libraries_through_the_run_paths_of_the_file_that_loaded_it
    files = mach_o do |build|
      build.dylib("vendor/libinner.dylib", install_name: "@rpath/libinner.dylib")
      build.dylib("vendor/libouter.dylib", install_name: "@rpath/libouter.dylib", links: ["vendor/libinner.dylib"])
      build.bundle("lib/ext.bundle", links: ["vendor/libouter.dylib"], rpaths: ["@loader_path/../vendor"])
    end

    assert_empty problems("darwin", files)
  end

  def test_a_loader_path_library_that_is_not_where_it_says_keeps_a_gem_from_shipping
    files = mach_o do |build|
      build.dylib("vendor/libfoo.dylib", install_name: "@loader_path/libfoo.dylib")
      build.bundle("lib/ext.bundle", links: ["vendor/libfoo.dylib"], rpaths: [])
    end

    assert_equal [
      "linked 1.0.0's lib/ext.bundle needs @loader_path/libfoo.dylib, which is not there: the gem carries libfoo.dylib at " \
        "vendor/libfoo.dylib, so the app could not load it on another computer. Build the gem so that the file names the " \
        "library where it is, such as @loader_path/../vendor/libfoo.dylib.",
    ], problems("darwin", files)
  end

  # The runtime's own libraries are where the runtime puts them, which is
  # the runtime's to get right, not the gem's.
  def test_an_rpath_library_the_runtime_ships_is_not_the_gems_to_reach
    files = mach_o do |build|
      build.dylib("build/libruntime.dylib", install_name: "@rpath/libruntime.dylib")
      build.bundle("lib/ext.bundle", links: ["build/libruntime.dylib"], rpaths: [])
    end

    assert_empty problems("darwin", files.except("build/libruntime.dylib"), provided: ["libruntime.dylib"])
  end

  # Where the program sits in the app depends on the app's kind, so a
  # library named from it is judged by its name alone, as before.
  def test_an_executable_path_run_path_is_not_judged
    files = mach_o do |build|
      build.dylib("vendor/libfoo.dylib", install_name: "@rpath/libfoo.dylib")
      build.bundle("lib/ext.bundle", links: ["vendor/libfoo.dylib"], rpaths: ["@executable_path/../lib"])
    end

    assert_empty problems("darwin", files)
  end

  # Builds Mach-O files with Xcode's clang, as a gem's own build would, by
  # their paths in the gem, and returns them with their bytes.
  def mach_o
    skip "builds its Mach-O files with Xcode's clang and install_name_tool, which only a Mac has" unless RUBY_PLATFORM.include?("darwin")
    Dir.mktmpdir("linkage") do |dir|
      build = MachOBuild.new(dir)
      yield build
      build.files
    end
  end

  # A gem's folder of Mach-O files that clang links against each other.
  class MachOBuild
    def initialize(dir)
      @dir = dir
      @paths = []
    end

    # A dynamic library at +path+, whose install name is +install_name+,
    # that links the libraries at +links+.
    def dylib(path, install_name:, links: [])
      link(path, ["-dynamiclib", "-install_name", install_name], links, [])
    end

    # A Ruby-style bundle at +path+ that links +links+ and has the run
    # paths +rpaths+, which install_name_tool adds as a gem's build would.
    def bundle(path, links:, rpaths:)
      link(path, ["-bundle"], links, rpaths)
    end

    def files
      @paths.to_h { |path| [path, File.binread(File.join(@dir, path))] }
    end

    private def link(path, kind, links, rpaths)
      output = File.join(@dir, path)
      FileUtils.mkdir_p(File.dirname(output))
      source = "#{output}.c"
      File.write(source, "void fixture_#{@paths.size}(void) {}\n")
      run("clang", "-arch", "arm64", "-mmacosx-version-min=14.0", "-headerpad_max_install_names", *kind, source, *links.map { |library| File.join(@dir, library) },
        "-o", output)
      File.delete(source)
      rpaths.each { |rpath| run("install_name_tool", "-add_rpath", rpath, output) }
      @paths << path
    end

    private def run(*command)
      output, status = Open3.capture2e(*command)
      raise "#{command.join(' ')} failed:\n#{output}" unless status.success?
    end
  end
end
