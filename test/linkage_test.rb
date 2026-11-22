# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/binaries"

# Whether a gem's compiled files would load on the computer an app goes
# to (Fledge::Linkage): files LLVM's linker made
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
  # distribution may be needed, on glibc's Linux and musl's,
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

  # On Android a library may need one the project lists as its host's,
  # which the host's own Gradle dependencies add to the APK where no
  # check of Fledge's reads it; one it could list, a name Android's
  # installer extracts, is named with the key (glibc's libc.so.6 is not,
  # test_an_android_library_may_need_only_what_android_offers_every_app_and_the_app_carries),
  # and one listed that nothing needs is refused.
  def test_an_android_library_may_need_one_the_project_lists_as_its_hosts
    TestReaders.need(self, :elf)
    files = { "lib/ext.so" => Binaries.elf(needed: %w[libc.so libSDL3.so]) }
    unlisted = Fledge::Linkage.new(os: "android", readers: TestReaders.all)
    assert_equal [
      "linked 1.0.0's lib/ext.so needs libSDL3.so, which neither Android, nor Fledge's runtime, nor the app's own native libraries " \
        "provide, so the app could not load it on a phone. Build the gem so that it carries the library, or links it statically, " \
        "or, when the app's host adds it through its own Gradle dependencies, list it in fledge.yml as android: { host_libraries: [libSDL3.so] }.",
    ], unlisted.problems("linked 1.0.0", files)

    linkage = Fledge::Linkage.new(os: "android", system: %w[libSDL3.so libunused.so], readers: TestReaders.all)
    assert_empty linkage.problems("linked 1.0.0", files)
    assert_equal [
      "fledge.yml's android: host_libraries lists libunused.so, which none of the app's native libraries, nor the gems' compiled " \
        "files, needs beyond what Android, Fledge's runtime, and the app's own native libraries provide. Remove it.",
    ], linkage.unused
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

  # On macOS the refusal names the setting that carries the library from
  # this computer, by its file name, as the Linux refusal names
  # system_libraries; a library the project lists there is no gem's
  # problem, by whatever path or run path the file names it, since
  # Fledge::CarriedLibraries finds and places it.
  def test_a_mac_app_may_carry_a_dylib_the_project_lists
    TestReaders.need(self, :macho)
    files = { "lib/ext.bundle" => Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib @rpath/libffi.dylib]) }
    refused = Fledge::Linkage.new(os: "darwin", readers: TestReaders.all).problems("linked 1.0.0", files)
    assert_equal [
"linked 1.0.0's lib/ext.bundle needs @rpath/libffi.dylib, which neither darwin, nor Fledge's runtime, nor the gem " \
  "itself provides, so the app could not load it on another computer. Build the gem so that it carries the library, or " \
  "links it statically, or, if you may distribute it, list it in fledge.yml as macos: { carried_libraries: [libffi.dylib] } " \
  "to have the app carry it from this computer.",
], refused

    assert_empty Fledge::Linkage.new(os: "darwin", carried: ["libffi.dylib"], readers: TestReaders.all).problems("linked 1.0.0", files)
    assert_equal 1, Fledge::Linkage.new(os: "darwin", carried: ["libother.dylib"], readers: TestReaders.all).problems("linked 1.0.0", files).size
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

  # LibUI's DLL, built with Visual Studio, draws with Direct2D and
  # DirectWrite, which are parts of Windows, and links Microsoft's
  # Visual C++ runtime, which is not: a computer has it only once
  # something installed the Visual C++ Redistributable. Both x64 and
  # ARM64 Windows have the first.
  def test_windows_provides_its_own_components_but_not_the_visual_c_runtime
    dll = Binaries.pe(needed: %w[d2d1.dll DWrite.dll msvcrt.dll WINDOWSCODECS.dll MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll])
    %w[windows windows-arm64].each do |os|
      unprovided = problems(os, { "vendor/libui.x64.dll" => dll }).map { |problem| problem[/needs (\S+),/, 1] }
      assert_equal %w[MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll], unprovided, os
    end
  end

  # An app's developer cannot rebuild someone else's gem, so the refusal
  # says what the DLL is and names the two ways fledge.yml ships it, and
  # the build of the gem that needs neither.
  def test_the_refusal_names_the_visual_c_runtime_and_the_key_that_ships_it
    dll = Binaries.pe(needed: %w[d2d1.dll DWrite.dll msvcrt.dll WINDOWSCODECS.dll MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll])
    found = problems("windows", { "vendor/libui.x64.dll" => dll })
    assert_equal %w[MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll], found.map { |text| text[/needs (\S+),/, 1] }
    assert_equal "linked 1.0.0's vendor/libui.x64.dll needs VCRUNTIME140.dll, of Microsoft's Visual C++ runtime, which Windows does " \
      "not include, so the app could not load it on a computer without the Visual C++ Redistributable. Set windows: " \
      "{ visual_c_runtime: local } in fledge.yml to copy the runtime from this computer into the app, if you may distribute it " \
      "(Microsoft limits that to licensed Visual Studio users), or windows: { visual_c_runtime: central } if every computer the " \
      "app goes to has the Redistributable; or use a build of the gem that links the runtime statically (/MT).",
      found[1]
  end

  # With either way chosen the runtime's DLLs are no gem's problem: the
  # check names them, once each, for the app to carry or the computer to
  # have, and still refuses any other DLL nothing provides.
  def test_a_chosen_visual_c_runtime_is_named_rather_than_refused
    TestReaders.need(self, :pe)
    %w[local central].each do |choice|
      linkage = Fledge::Linkage.new(os: "windows", provided: ["x64-ucrt-ruby400.dll"], readers: TestReaders.all, visual_c_runtime: choice)
      found = linkage.problems("linked 1.0.0", {
        "vendor/libui.x64.dll" => Binaries.pe(needed: %w[d2d1.dll DWrite.dll msvcrt.dll WINDOWSCODECS.dll MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll]),
        "vendor/other.dll" => Binaries.pe(needed: %w[MSVCP140.dll KERNEL32.dll]),
        "lib/ext.so" => Binaries.pe(needed: %w[x64-ucrt-ruby400.dll KERNEL32.dll api-ms-win-crt-heap-l1-1-0.dll libxml2-16.dll]),
      })
      assert_equal [], found.grep(/Visual C\+\+/), choice
      assert_equal 1, found.grep(/libxml2-16\.dll/).size, choice
      assert_equal %w[MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll], linkage.visual_c_libraries, choice
    end
  end

  # An Android app's native library may need the NDK's public libraries
  # for the API level the runtime is built for, Fledge's
  # libfledgeruby.so, and the libraries the app carries beside it; a
  # library of a desktop's Linux, such as glibc's libc.so.6, or one
  # nothing carries, keeps it from shipping, and Android has no
  # distribution to list one from.
  def test_an_android_library_may_need_only_what_android_offers_every_app_and_the_app_carries
    assert_empty problems("android", {
      "ext/x86_64-linux/libheld.so" => Binaries.elf(needed: %w[liblog.so libz.so libdl.so libm.so libc.so]),
      "ext/x86_64-linux/libown.so" => Binaries.elf(needed: %w[libc.so]),
    })
    android = problems("android", {
      "ext/x86_64-linux/libheld.so" => Binaries.elf(needed: %w[libc.so.6 libcrypt.so.2 libxml2.so.2 libown.so]),
    }, provided: %w[libfledgeruby.so libcrypt.so.2 libown.so])
    assert_equal %w[libc.so.6 libxml2.so.2].map { |library|
      "linked 1.0.0's ext/x86_64-linux/libheld.so needs #{library}, which neither Android, nor Fledge's runtime, nor the app's " \
        "own native libraries provide, so the app could not load it on a phone. Build the gem so that it carries the library, " \
        "or links it statically."
    }, android
  end

  # raylib-bindings carries libraylib as lib/libraylib.x86_64.so, whose
  # SONAME is libraylib.so.600, and its raygui and physac libraries need
  # libraylib.so.600, a name no file of the gem has. The gem loads
  # libraylib first, by its path, and glibc's loader then gives a later
  # need of that name the library already loaded under it (_dl_map_object
  # in glibc 2.39's elf/dl-load.c): the gem runs, and is not refused.
  # Without the library that names itself so, the need is refused, and
  # on musl's Linux, whose loader's source was not read for this, too.
  def test_a_library_the_gem_carries_under_another_file_name_answers_to_its_soname_on_linux
    raygui = Binaries.elf(needed: %w[libraylib.so.600 libc.so.6])

    assert_empty problems("linux", {
      "lib/libraylib.x86_64.so" => Binaries.elf(needed: %w[libc.so.6], soname: "libraylib.so.600"),
      "lib/raygui.x86_64.so" => raygui,
    })
    assert_equal 1, problems("linux", { "lib/raygui.x86_64.so" => raygui }).size
    musl = problems("linux-musl", {
      "lib/libraylib.x86_64.so" => Binaries.elf(needed: %w[libc.so.6], soname: "libraylib.so.600"),
      "lib/raygui.x86_64.so" => raygui,
    })
    assert(musl.any? { |problem| problem.include?("lib/raygui.x86_64.so needs libraylib.so.600") }, musl.join("\n"))
  end

  # On macOS, dyld gives a need of @rpath/NAME an image already loaded
  # whose install name is that, before it searches any run path
  # (Loader::getLoader in dyld-1378's Loader.cpp), as raylib-bindings'
  # raygui.arm64.dylib finds libraylib.arm64.dylib, whose install name is
  # @rpath/libraylib.600.dylib. dyld does so for @rpath alone: a need of
  # @loader_path/NAME is looked for as a file, which the gem does not
  # have, whatever the install name of the copy it does have.
  def test_a_dylib_the_gem_carries_under_another_file_name_answers_to_its_rpath_install_name_on_macos
    assert_empty problems("darwin", {
      "lib/libraylib.arm64.dylib" => Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib], install_name: "@rpath/libraylib.600.dylib"),
      "lib/raygui.arm64.dylib" => Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib @rpath/libraylib.600.dylib]),
    })

    refused = problems("darwin", {
      "lib/libraylib.arm64.dylib" => Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib], install_name: "@loader_path/libraylib.600.dylib"),
      "lib/raygui.arm64.dylib" => Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib @loader_path/libraylib.600.dylib]),
    })
    assert_equal 1, refused.size
    assert_includes refused.first, "lib/raygui.arm64.dylib needs @loader_path/libraylib.600.dylib, which neither darwin"
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
  # like any other.
  def test_code_compiled_in_is_not_judged
    iconv = "UCS-4-INTERNAL MULELAO-1 GNU MP: Cannot allocate memory yescrypt-ROMhash"

    assert_empty problems("linux", { "lib/ext.so" => Binaries.elf(needed: ["libc.so.6"], payload: iconv) })
  end

  # A process loads only code for its own processor, so a gem's library
  # for another, beside its own (raylib-bindings carries
  # lib/libraylib.x86_64.so and lib/libraylib.aarch64.so, and its Ruby
  # picks one), is never loaded and never judged: neither for what it
  # needs, nor as the gem's copy of a library another file needs. The
  # app's own processor's files are judged as ever, and a 32-bit file is
  # another processor's, since a 64-bit process loads none.
  def test_a_file_for_another_processor_is_never_loaded_and_never_judged
    TestReaders.need(self, :elf)
    files = {
      "lib/libray.x86_64.so" => Binaries.elf(needed: %w[libc.so.6]),
      "lib/libray.aarch64.so" => Binaries.elf(needed: %w[libc.so.6 libGLX.so.0], cpu: "aarch64"),
      "lib/libray.i386.so" => Binaries.elf(needed: %w[libc.so.6 libGLX.so.0], cpu: "i386"),
      "lib/libray.armhf.so" => Binaries.elf(needed: %w[libc.so.6 libGLX.so.0], cpu: "arm"),
    }
    judged = lambda do |cpu, gem|
      Fledge::Linkage.new(os: "linux", cpu:, readers: TestReaders.all).problems("linked 1.0.0", gem).map { |problem| problem[/\S+\.so/] }
    end

    assert_equal %w[lib/libray.aarch64.so lib/libray.armhf.so lib/libray.i386.so], judged.call(nil, files)
    assert_empty judged.call("x86_64", files)
    assert_equal %w[lib/libray.aarch64.so], judged.call("aarch64", files)

    carried = { "lib/ext.so" => Binaries.elf(needed: %w[libc.so.6 libxml2.so.2]), "lib/arm/libxml2.so.2" => files.fetch("lib/libray.aarch64.so") }
    unprovided = lambda do |cpu|
      Fledge::Linkage.new(os: "linux", cpu:, readers: TestReaders.all).problems("linked 1.0.0", carried).grep(/needs libxml2/).size
    end
    assert_equal [0, 1], [unprovided.call(nil), unprovided.call("x86_64")]
  end

  # The same holds of Mach-O and PE: an Intel bundle on an arm64 Mac,
  # whose Ruby Rosetta does not translate, and an ARM64 DLL in an x64
  # app, or an x64 one in an ARM64 app.
  def test_a_mach_o_or_pe_file_for_another_processor_is_never_judged
    TestReaders.need(self, :macho, :pe)
    intel = Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib /usr/local/opt/libxml2/lib/libxml2.2.dylib], cpu: "x86_64")
    arm = Binaries.pe(needed: %w[KERNEL32.dll libxml2-16.dll], cpu: "aarch64")
    x64 = Binaries.pe(needed: %w[libgmp-10.dll KERNEL32.dll])
    judged = -> (os, cpu, file) { Fledge::Linkage.new(os:, cpu:, readers: TestReaders.all).problems("linked 1.0.0", { "lib/ext" => file }).size }

    assert_equal [1, 0, 1], [judged.call("darwin", nil, intel), judged.call("darwin", "aarch64", intel), judged.call("darwin", "x86_64", intel)]
    assert_equal [0, 1], [judged.call("windows", "x86_64", arm), judged.call("windows-arm64", "aarch64", arm)]
    assert_equal [1, 0], [judged.call("windows", "x86_64", x64), judged.call("windows-arm64", "aarch64", x64)]
  end

  # On Windows a DLL of the runtime's counts only where the app's Ruby
  # searches for one an extension imports by name (RuntimeContents#libraries):
  # a gem's DLL that needs libgmp-10.dll loads with the runtime's copy in
  # ruby_builtin_dlls, and is refused when the runtime holds it only
  # beside another gem's extension, where Windows would not look.
  def test_on_windows_a_runtime_dll_counts_only_where_the_apps_ruby_searches
    TestReaders.need(self, :pe)
    windows = Fledge::Platform.find("x64-mingw-ucrt")
    dll = Binaries.pe(needed: %w[libgmp-10.dll KERNEL32.dll])
    Dir.mktmpdir do |dir|
      judged = lambda do |place|
        runtime = Fledge::RuntimeContents.read(FakeRuntime.write(dir, windows, extra: [Fledge::Entry.file(place, "MZ")]))
        Fledge::Linkage.new(os: "windows", cpu: "x86_64", provided: runtime.libraries, readers: TestReaders.all)
          .problems("linked 1.0.0", { "lib/linked.so" => dll })
      end

      assert_empty judged.call("ruby/bin/ruby_builtin_dlls/libgmp-10.dll")
      refusal = "linked 1.0.0's lib/linked.so needs libgmp-10.dll, which neither windows, nor Fledge's runtime, nor the gem " \
        "itself provides, so the app could not load it on another computer. Build the gem so that it carries the library, or " \
        "links it statically."
      assert_equal [refusal], judged.call("ruby/lib/ruby/gems/4.1.0+5/extensions/x64-mingw-ucrt/4.1.0+5/fiddle-1.1.8/libgmp-10.dll")
    end
  end

  # A loader loads only its own system's format, so a Linux gem's copy of
  # a Windows DLL, say, is never loaded and never judged.
  def test_a_file_for_another_systems_loader_is_never_judged
    assert_empty problems("linux", { "vendor/win/ext.dll" => Binaries.pe(needed: %w[libgmp-10.dll KERNEL32.dll]) })
  end
end
