# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "json"
require "open3"
require "stringio"
require_relative "../support/android"
require_relative "../support/ios"

# Native gems on phones (doc/contributors/design/phone-projects.md,
# "Gems with extensions"), compiled for real: a gem's extension for
# every target of a phone, with the real mobile runtimes and tools
# where this computer has them. test/mobile_extensions_test.rb covers
# which extensions Fledge compiles and how it writes what links them.
# The Android tests skip without the Android runtime, the NDK, CMake, or
# Rust's Android targets, and fail instead where FLEDGE_REQUIRE_ANDROID
# is set, as in CI's Mobile apps (Android emulator) job, which has them
# all (AndroidRequired). The iOS tests skip off a Mac, or without the
# iOS runtime, CMake, or Rust's iOS targets, and fail instead where
# FLEDGE_REQUIRE_IOS is set, as in CI's Mobile apps (iOS Simulator) job,
# which has them all (IOSRequired).
class MobileExtensionsBuildTest < Minitest::Test
  include AndroidRequired
  include IOSRequired

  # The folder by its long names, as Dir.glob names what it finds in it
  # (Fledge::LongPath), where Windows' TMP names it by an 8.3 name.
  def setup
    @dir = Fledge::LongPath.of(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def ios = Fledge::MobilePlatform.find("ios")
  def android = Fledge::MobilePlatform.find("android")

  # The real tools: Xcode and a built iOS runtime, as rake runtime writes
  # it, and the desktop runtime of this Mac, whose Ruby runs mkmf.
  # Without the iOS runtime they skip even where FLEDGE_REQUIRE_RUNTIME
  # is set, since that asks for this computer's own runtime, the one CI's
  # Test jobs download. Those jobs run on macos-15, which has neither the
  # Xcode runtime/sources.yml pins nor XcodeGen. The Mobile apps (iOS
  # Simulator) job has both, and the iOS runtime, and runs these tests
  # with FLEDGE_REQUIRE_IOS set.
  def test_a_c_extension_is_compiled_for_the_device_and_the_simulator
    runtimes = real_runtimes("ios")
    greeter = File.expand_path("../../examples/native_phone/gems/adder", __dir__)
    spec_package = Fledge::PathPackage.new(path_gem(greeter))
    built = compile(runtimes, ios, { path_gem(greeter) => spec_package })

    assert_equal [["adder/adder", "Init_fledge_0"]], built.registrations
    assert_equal ["app/vendor/cache/adder/lib/adder/adder.rb"], built.stubs.map(&:path)
    assert_equal %w[ios-arm64 ios-arm64-simulator], built.targets.keys
    platforms = built.targets.transform_values do |target|
      archive = target.archives.fetch(0)
      assert_includes Open3.capture2("xcrun", "nm", archive).first, " T _Init_fledge_0"
      object = Dir.glob(File.join(File.dirname(archive), "*.o")).first.to_s
      Open3.capture2("xcrun", "vtool", "-show-build", object).first[/platform (\S+)/, 1]
    end
    assert_equal({ "ios-arm64" => "IOS", "ios-arm64-simulator" => "IOSSIMULATOR" }, platforms)
  end

  # A phone runtime's rbconfig.rb records the folders of the computer that
  # built it: libffi's headers and library in CPPFLAGS and LDFLAGS, and
  # each library's folder as a --with-NAME-dir option, which mkmf would
  # search for every gem. What Ruby reads after the shim's tools keeps
  # every other flag and option, and the runtime's own folders.
  def test_the_folders_of_the_computer_that_built_a_runtime_leave_its_rbconfig
    arch = File.join(@dir, "lib", "ruby", "4.1.0", "arm64-darwin")
    FileUtils.mkdir_p(arch)
    built = "/Users/runner/work/Fledge/tmp/runtime/ios"
    File.write(File.join(arch, "rbconfig.rb"), <<~RUBY)
      module RbConfig
        TOPDIR = #{@dir.inspect}
        CONFIG = {
          "CPPFLAGS" => "-I#{built}/stub -I #{built}/libffi/include -I#{@dir}/include -D_REENTRANT $(DEFS) $(cppflags)",
          "LDFLAGS" => "-L. -framework Security -L#{built}/libffi/lib -fstack-protector-strong",
          "DLDFLAGS" => "-framework Security -L#{built}/libffi/lib",
          "configure_args" => " '--prefix=/' '--with-openssl-dir=#{built}/openssl' '--with-libffi-dir=#{built}/libffi' '--without-gmp' 'PKG_CONFIG=false'",
        }
        MAKEFILE_CONFIG = CONFIG.transform_values(&:dup)
      end
    RUBY
    shim = File.join(@dir, "tools.rb")
    File.write(shim, Fledge::MobileExtensions::TOOLS)
    script = 'require "json"; puts JSON.generate [RbConfig::CONFIG, RbConfig::MAKEFILE_CONFIG].map { |c| [*c.values_at("CPPFLAGS", "LDFLAGS", "DLDFLAGS"), c["configure_args"].shellsplit] }'

    output, status = Open3.capture2e({ "RUBYOPT" => nil, "RUBYLIB" => nil }, RbConfig.ruby, "--disable-gems", "-I", arch, "-r", shim, "-e", script)

    assert status.success?, output
    expected = [
      "-I#{@dir}/include -D_REENTRANT $(DEFS) $(cppflags)",
      "-L. -framework Security -fstack-protector-strong",
      "-framework Security ",
      %w[--prefix=/ --without-gmp PKG_CONFIG=false],
    ]
    assert_equal [expected, expected], JSON.parse(output)
  end

  # A phone runtime's rbconfig.rb records the folders of the computer that
  # built it, libffi's among them, which mkmf would search for every gem.
  # Where those folders still are, as where the runtime was built, the
  # ffi gem's extconf.rb found that libffi, and the app's link, which has
  # no such folder, failed (unable to find library -lffi). A libffi there
  # is found for the gem only when its build names the folder itself.
  # The libffi is a text stub ld64 links against, defining the function
  # for both slices.
  IOS_LIBFFI = <<~TBD
    --- !tapi-tbd
    tbd-version: 4
    targets: [ arm64-ios, arm64-ios-simulator ]
    install-name: '/usr/lib/libffi.dylib'
    exports:
      - targets: [ arm64-ios, arm64-ios-simulator ]
        symbols: [ _ffi_prep_closure_loc ]
    ...
  TBD

  def test_a_libffi_where_the_ios_runtime_was_built_is_not_found_for_an_extension
    flags = flags_with_the_runtime_builders_libffi(real_runtimes("ios"), ios, "libffi.tbd", IOS_LIBFFI)

    assert_equal %w[ios-arm64 ios-arm64-simulator], flags.keys
    flags.each { |slice, list| refute_includes list, "-lffi", slice }
  end

  def test_a_libffi_an_ios_gems_build_names_is_found
    flags = flags_with_the_runtime_builders_libffi(real_runtimes("ios"), ios, "libffi.tbd", IOS_LIBFFI, own: true)

    flags.each { |slice, list| assert_includes list, "-lffi", slice }
  end

  # The same on Android, where the libffi is a linker script that lld
  # reads as a library and that defines the function for any ABI.
  def test_a_libffi_where_the_android_runtime_was_built_is_not_found_for_an_extension
    runtimes = real_runtimes("android")
    android_ndk
    flags = flags_with_the_runtime_builders_libffi(runtimes, android, "libffi.so", "ffi_prep_closure_loc = 0;\n")

    assert_equal %w[aarch64-linux-android x86_64-linux-android], flags.keys
    flags.each { |abi, list| refute_includes list, "-lffi", abi }
  end

  def test_a_libffi_an_android_gems_build_names_is_found
    runtimes = real_runtimes("android")
    android_ndk
    flags = flags_with_the_runtime_builders_libffi(runtimes, android, "libffi.so", "ffi_prep_closure_loc = 0;\n", own: true)

    flags.each { |abi, list| assert_includes list, "-lffi", abi }
  end

  # Built as files, an Android extension is what a desktop's mkmf makes:
  # a shared object that keeps its own Init function, which Ruby's dln
  # looks up, and needs the runtime's libfledgeruby.so, which the app
  # has already loaded, for Ruby's C API. Having C++, it needs the
  # NDK's shared C++ runtime, which the app carries, as every C++
  # library of the app does; finds a library it links beside itself;
  # and aligns its LOAD segments for 16 KB pages.
  # It registers nothing and needs no Ruby file at its path: a link is
  # made there, where a desktop's RubyGems leaves its file.
  def test_an_android_extension_built_as_a_file_is_a_shared_object_with_its_own_init_function
    runtimes = real_runtimes("android")
    ndk = android_ndk
    adder = File.expand_path("../../examples/native_phone/gems/adder", __dir__)

    built = compile(runtimes, android, { path_gem(adder) => Fledge::PathPackage.new(path_gem(adder)) }, files: true)

    assert_equal [], built.registrations
    assert_equal [], built.stubs
    readelf = File.join(ndk.bin, "llvm-readelf")
    machines = built.targets.to_h do |name, target|
      assert_equal [], target.archives
      library = target.libraries.fetch(0)
      assert_equal ["adder/adder", ["app/vendor/cache/adder/lib/adder/adder.so"]], [library.feature, library.links]
      dynamic = Open3.capture2(readelf, "-d", "--dyn-syms", "-lW", library.path).first
      assert_match(/\d+ FUNC\s+GLOBAL\s+DEFAULT\s+\d+ Init_adder$/, dynamic, "#{name}: dln finds the extension's own Init function")
      assert_includes dynamic, "Shared library: [libfledgeruby.so]", "#{name}: Ruby is the runtime's"
      assert_includes dynamic, "Shared library: [libc++_shared.so]", "#{name}: the shared C++ runtime"
      assert_match(/\(RUNPATH\)\s+Library runpath: \[\$ORIGIN\]/, dynamic, "#{name}: what it links is found beside it")
      alignments = dynamic.lines.grep(/\A\s*LOAD\s/).map { |line| Integer(line.split.last) }
      assert_operator alignments.min, :>=, 16_384, "#{name}: aligned for 16 KB pages"
      [name, Open3.capture2(readelf, "-h", library.path).first[/Machine:\s+(.+)$/, 1]]
    end
    assert_equal({ "aarch64-linux-android" => "AArch64", "x86_64-linux-android" => "Advanced Micro Devices X86-64" }, machines)
  end

  # An extconf.rb may run strip on what it links, by that plain name, as
  # sassc 2.4.0's adds "strip -x $@" to mkmf's link off Apple's systems.
  # On a desktop that is the strip for the file; for Android it is the
  # NDK's, which reads the ABI's ELF, where this computer's refused it
  # ("Unable to recognise the format of the input file").
  def test_an_android_extconf_that_strips_its_library_strips_it_with_the_ndks_strip
    runtimes = real_runtimes("android")
    ndk = android_ndk
    extconf = "require \"mkmf\"\nMakeMakefile::LINK_SO << \"\\nstrip -x $@\"\ncreate_makefile(\"stripped/stripped\")\n"
    source = <<~C
      #include <ruby.h>
      static VALUE kept(VALUE self) { return Qtrue; }
      void Init_stripped(void) { rb_define_global_function("kept", kept, 0); }
    C
    gem = extconf_gem("stripped", extconf, { "stripped.c" => source })

    built = compile(runtimes, android, { gem => Fledge::PathPackage.new(gem) }, files: true)

    locals = built.targets.transform_values do |target|
      symbols = Open3.capture2(File.join(ndk.bin, "llvm-nm"), "--defined-only", target.libraries.fetch(0).path).first
      symbols.lines.map(&:split).select { |fields| fields[-2] == "t" }.map(&:last)
    end
    assert_equal({ "aarch64-linux-android" => [], "x86_64-linux-android" => [] }, locals, "strip -x left no local symbol")
  end

  # A C extension over a C++ library names a desktop's C++ runtime
  # (-lstdc++); built as a file, it links the NDK's shared C++ runtime in
  # its place, as a C++ extension and libfledgeext.so do.
  def test_an_android_c_extension_over_a_cpp_library_built_as_a_file_links_the_shared_cpp_runtime
    runtimes = real_runtimes("android")
    android_missing("examples/cmake_phone needs CMake on the PATH") unless cmake?
    ndk = android_ndk

    built = compile(runtimes, android, { tally_gem => Fledge::PathPackage.new(tally_gem) }, files: true)

    readelf = File.join(ndk.bin, "llvm-readelf")
    built.targets.each do |name, target|
      dynamic = Open3.capture2(readelf, "-d", "--dyn-syms", target.libraries.fetch(0).path).first
      assert_includes dynamic, "Shared library: [libc++_shared.so]", "#{name}: the shared C++ runtime"
      assert_match(/UND\s+(?:_ZNSt|_Znwm|_ZdlPv|__gxx_personality)/, dynamic, "#{name}: the C++ runtime is not linked in")
      refute_match(/UND\s+tally_/, dynamic, "#{name}: the library's code is linked in")
    end
  end

  # An extconf.rb that writes extconf.h, as many do, takes mkmf's $defs
  # off the compile line (mkmf.rb's create_makefile), so the extension's
  # Init function is still renamed only if the rename goes elsewhere.
  def test_an_extconf_that_writes_its_header_has_its_init_function_renamed
    runtimes = real_runtimes("ios")
    gem = extconf_gem("headed", <<~RUBY, "headed.c" => "#include <ruby.h>\nvoid Init_headed(void) { rb_define_module(\"Headed\"); }\n")
      require "mkmf"
      have_header("stdint.h")
      create_header
      create_makefile("headed/headed")
    RUBY

    built = compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) })

    assert_equal [["headed/headed", "Init_fledge_0"]], built.registrations
    built.targets.each_value do |target|
      symbols = Open3.capture2("xcrun", "nm", "-g", "--defined-only", target.archives.fetch(0)).first
      assert_match(/ T _Init_fledge_0$/, symbols)
      refute_match(/ T _Init_headed$/, symbols)
    end
  end

  # The ffi gem's extconf.rb appends a makefile to the one mkmf wrote,
  # which builds its own libffi with configure, given the compiler only
  # in the environment, and adds the library to LOCAL_LIBS. This gem's
  # does the same with one C file: the library is built for each slice
  # by the phone's compiler, and linked with the extension.
  def test_a_library_an_extconf_adds_to_its_makefile_is_built_and_linked_for_each_ios_slice
    runtimes = real_runtimes("ios")
    gem = extconf_gem("twice", <<~RUBY, "twice.c" => <<~C, "lib.c" => "int twice_lib(int n) { return 2 * n; }\n", "lib.mk" => <<~MAKE)
      require "mkmf"
      create_makefile("twice/twice")
      File.open("Makefile", "a") { |makefile| makefile.puts "include $(srcdir)/lib.mk" }
    RUBY
      #include <ruby.h>
      int twice_lib(int n);
      static VALUE twice(VALUE self, VALUE n) { return INT2FIX(twice_lib(FIX2INT(n))); }
      void Init_twice(void) { rb_define_module_function(rb_define_module("Twice"), "twice", twice, 1); }
    C
      LIBTWICE = $(shell pwd)/libtwice/libtwice.a
      LOCAL_LIBS += "$(LIBTWICE)"
      $(OBJS): $(LIBTWICE)
      $(LIBTWICE):
      \tmkdir -p $(@D) && $$CC -c $(srcdir)/lib.c -o $(@D)/lib.o && $${AR:-ar} rcs $@ $(@D)/lib.o
    MAKE

    built = compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) })

    platforms = built.targets.transform_values do |target|
      library = target.archives.find { |path| File.basename(path) == "libtwice.a" } or flunk "#{target.archives} has no libtwice.a"
      assert_includes Open3.capture2("xcrun", "nm", library).first, " T _twice_lib"
      Open3.capture2("xcrun", "vtool", "-show-build", File.join(File.dirname(library), "lib.o")).first[/platform (\S+)/, 1]
    end
    assert_equal({ "ios-arm64" => "IOS", "ios-arm64-simulator" => "IOSSIMULATOR" }, platforms)
  end

  # examples/cmake_phone's extconf.rb runs CMake, which builds its C++
  # library from CMAKE_TOOLCHAIN_FILE for each slice (doc/contributors/design/phone-projects.md,
  # "CMake toolchain files"): the
  # device's objects are for iOS and the Simulator's for the Simulator,
  # as each slice's extension is.
  def test_a_cmake_library_an_extconf_builds_is_built_for_each_ios_slice
    runtimes = real_runtimes("ios")
    ios_missing("examples/cmake_phone needs CMake on the PATH") unless cmake?
    built = compile(runtimes, ios, { tally_gem => Fledge::PathPackage.new(tally_gem) })

    assert_equal [["tally/tally", "Init_fledge_0"]], built.registrations
    platforms = built.targets.transform_values do |target|
      library = target.archives.find { |archive| File.basename(archive) == "libtally.a" } or flunk "no libtally.a in #{target.archives}"
      assert target.cxx, "the extension names the C++ runtime"
      refute_includes target.flags, "-lc++"
      object = Dir.glob(File.join(File.dirname(library), "**", "tally.cc.o")).first.to_s
      Open3.capture2("xcrun", "vtool", "-show-build", object).first[/platform (\S+)/, 1]
    end
    assert_equal({ "ios-arm64" => "IOS", "ios-arm64-simulator" => "IOSSIMULATOR" }, platforms)
  end

  # The same for each Android ABI with the NDK, where this computer has
  # one: libfledgeext.so holds the library's code, over the NDK's shared
  # C++ runtime, which the app then carries, stripped, once for each
  # ABI, with its notice, though no other library of the app needs it.
  def test_a_cmake_library_an_extconf_builds_is_linked_for_each_android_abi
    runtimes = real_runtimes("android")
    android_missing("examples/cmake_phone needs CMake on the PATH") unless cmake?
    ndk = android_ndk
    built = compile(runtimes, android, { tally_gem => Fledge::PathPackage.new(tally_gem) })
    registration = File.join(@dir, "registration.c")
    File.write(registration, Fledge::MobileExtensions.registration_source(built.registrations))
    compiler = Fledge::MobileExtensions.new(platform: android, packages: {}, build_args: {}, host: Fledge::Platform.local,
      runtimes: Fledge::Runtimes.new(env: ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes)), work: File.join(@dir, "work"), log: StringIO.new,
      gem_dir: "lib/ruby/gems/4.1.0+5")
    project = File.join(@dir, "project")
    FileUtils.mkdir_p(ruby_root = File.join(project, "fledge"))
    readelf = File.join(ndk.bin, "llvm-readelf")
    machines = built.targets.to_h do |name, build|
      into = File.join(project, "src", "main", "jniLibs", build.target.abi, "libfledgeext.so")
      library = compiler.shared_library(built, build, registration:, into:)
      dynamic = Open3.capture2(readelf, "-d", "--dyn-syms", library).first
      refute_match(/UND\s+tally_/, dynamic, "#{name}: the library's code is linked in")
      assert_includes dynamic, "Shared library: [libc++_shared.so]", "#{name}: the shared C++ runtime"
      assert_match(/UND\s+(?:_ZNSt|_Znwm|_ZdlPv|__gxx_personality)/, dynamic, "#{name}: the C++ runtime is not linked in")
      assert_match(/\(RUNPATH\)\s+Library runpath: \[\$ORIGIN\]/, dynamic, "#{name}: the ruby program finds what it needs beside it")
      [name, Open3.capture2(readelf, "-h", library).first[/Machine:\s+(.+)$/, 1]]
    end
    assert_equal({ "aarch64-linux-android" => "AArch64", "x86_64-linux-android" => "Advanced Micro Devices X86-64" }, machines)
    Fledge::MobileProject::AndroidLibraries.new(built).carry_cxx_runtime(project, ruby_root:)
    built.targets.each_value do |build|
      assert_equal ["libc++_shared.so", "libfledgeext.so"], Dir.children(File.join(project, "src", "main", "jniLibs", build.target.abi)).sort
      assert_carries_stripped_cxx_runtime(ndk, project, build)
    end
    assert_path_exists File.join(ruby_root, "notices", "libc++_shared.txt")
  end

  # A Rakefile shaped like digest-crc's runs an extconf.rb and make in
  # the folder of each extension, and leaves each where the gem's require
  # path ext finds it. RubyGems' builder runs it with the phone's
  # rbconfig.rb, the compiler wrapper turns each shared link into an
  # archive for the slice, and each extension registers under the name
  # its path gives it, its Init function renamed.
  def test_the_extensions_a_rakefile_builds_are_archived_for_each_ios_slice
    runtimes = real_runtimes("ios")
    built = compile(runtimes, ios, { rakesum_gem => Fledge::PathPackage.new(rakesum_gem) })

    assert_equal [%w[rakesum/adler/adler_ext Init_fledge_0_adler_ext], %w[rakesum/fletcher/fletcher_ext Init_fledge_0_fletcher_ext]],
      built.registrations.sort
    assert_empty built.stubs, "RubyGems copies no Rakefile's extension into the gem's require path"
    platforms = built.targets.transform_values do |target|
      assert_equal 2, target.archives.size
      target.archives.map do |archive|
        symbols = Open3.capture2("xcrun", "nm", "-g", "--defined-only", archive).first
        assert_match(/ T _Init_fledge_0_(?:adler|fletcher)_ext$/, symbols)
        refute_match(/ T _Init_(?:adler|fletcher)_ext$/, symbols, "the extension's own Init function is renamed")
        members = File.join(@dir, "members", File.basename(archive))
        FileUtils.mkdir_p(members)
        system("ar", "-x", archive, chdir: members, exception: true)
        object = Dir.children(members).find { |member| member.end_with?(".o") }.to_s
        Open3.capture2("xcrun", "vtool", "-show-build", File.join(members, object)).first[/platform (\S+)/, 1]
      end.uniq
    end
    assert_equal({ "ios-arm64" => ["IOS"], "ios-arm64-simulator" => ["IOSSIMULATOR"] }, platforms)
  end

  # A Rakefile that links a library for Ruby's ffi, as ffi-compiler's
  # tasks do with the compiler in CC, makes no extension of Ruby's: the
  # build finds the library it wrote in the gem, built for each slice,
  # and the path in the app where the gem looks for it, which the iOS
  # project makes a framework of its own (test/ios_libraries_test.rb).
  def test_a_library_for_ffi_a_rakefile_links_is_found_for_each_ios_slice
    runtimes = real_runtimes("ios")
    gem = rake_gem("thing", THING_RAKEFILE, files: { "thing.c" => "int thing(void) { return 1; }\n" })

    built = compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) })

    platforms = built.targets.transform_values do |target|
      library = target.ffi_libraries.fetch(0)
      assert_equal ["thing", "ext/libthing.so", ["app/vendor/cache/thing/ext/libthing.so"]], [library.gem, library.file, library.links]
      Open3.capture2("xcrun", "vtool", "-show-build", library.path).first[/platform (\S+)/, 1]
    end
    assert_equal({ "ios-arm64" => "IOS", "ios-arm64-simulator" => "IOSSIMULATOR" }, platforms)
  end

  # ffi-compiler links with -bundle on every Apple system, through the
  # compiler in CC, and a Rakefile may link through rbconfig.rb's: on iOS
  # each comes out a dynamic library, the only binary a framework holds,
  # for the slice it was built for.
  def test_a_bundle_a_rakefile_links_for_ios_is_a_dynamic_library
    runtimes = real_runtimes("ios")
    rakefile = <<~'RAKEFILE'
      task :default do
        sh "#{ENV['CC']} -c thing.c -o thing.o"
        sh "#{ENV['CC']} -bundle -o libthing.bundle thing.o"
        sh "#{RbConfig::CONFIG['CC']} -bundle -o libother.bundle thing.o"
      end
    RAKEFILE
    gem = rake_gem("thing", rakefile, files: { "thing.c" => "int thing(void) { return 1; }\n" })

    built = compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) })

    kinds = built.targets.transform_values do |target|
      target.ffi_libraries.sort_by(&:file).map do |library|
        header = Open3.capture2("xcrun", "otool", "-hv", library.path).first.lines.last.split
        platform = Open3.capture2("xcrun", "vtool", "-show-build", library.path).first[/platform (\S+)/, 1]
        [library.file, header[4], platform]
      end
    end
    assert_equal({
      "ios-arm64" => [["ext/libother.bundle", "DYLIB", "IOS"], ["ext/libthing.bundle", "DYLIB", "IOS"]],
      "ios-arm64-simulator" => [["ext/libother.bundle", "DYLIB", "IOSSIMULATOR"], ["ext/libthing.bundle", "DYLIB", "IOSSIMULATOR"]],
    }, kinds)
  end

  # An extconf.rb may build a library for Ruby's ffi with mkmf, which
  # defines no Init function and links no libruby, as sassc's builds
  # libsass. On iOS it registers nothing and gets no Ruby file at its
  # path: it is a dynamic library for each slice, at the path where a
  # desktop's RubyGems copies it into the gem's lib/.
  def test_an_extconf_library_with_no_init_function_is_a_library_for_ffi_on_ios
    runtimes = real_runtimes("ios")
    extconf = "require \"mkmf\"\n$LIBRUBYARG = nil\ncreate_makefile(\"plain/libplain\")\n"
    gem = extconf_gem("plain", extconf, { "plain.c" => "int plain(void) { return 1; }\n" })

    built = compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) })

    assert_empty built.registrations
    assert_empty built.stubs
    kinds = built.targets.transform_values do |target|
      library = target.ffi_libraries.fetch(0)
      header = Open3.capture2("xcrun", "otool", "-hv", library.path).first.lines.last.split
      platform = Open3.capture2("xcrun", "vtool", "-show-build", library.path).first[/platform (\S+)/, 1]
      [target.archives, library.file, library.links, header[4], platform]
    end
    links = ["app/vendor/cache/plain/lib/plain/libplain.bundle"]
    assert_equal({
      "ios-arm64" => [[], "lib/plain/libplain.bundle", links, "DYLIB", "IOS"],
      "ios-arm64-simulator" => [[], "lib/plain/libplain.bundle", links, "DYLIB", "IOSSIMULATOR"],
    }, kinds)
  end

  # A package may hold a library at the path its Rakefile writes, as
  # llhttp-ffi 0.5.1's holds one its author built on a Mac. Ruby's ffi
  # takes iOS for darwin, so a gem would ask dlopen for that library on
  # an iPhone: a build that leaves it as it was is refused, naming it.
  def test_a_macos_library_a_package_holds_and_its_rakefile_leaves_is_refused_for_ios
    runtimes = real_runtimes("ios")
    gem = rake_gem("thing", "task :default\n",
      files: { "thing.c" => "int thing(void) { return 1; }\n", "aarch64-darwin/libthing.bundle" => "" })
    folder = File.join(@dir, "gems", "thing", "ext")
    system("xcrun", "clang", "-bundle", "-o", File.join(folder, "aarch64-darwin", "libthing.bundle"), File.join(folder, "thing.c"),
      exception: true)

    error = assert_raises(Fledge::Error) { compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) }) }

    assert_includes error.message, "thing 1.0.0's Rakefile left ext/aarch64-darwin/libthing.bundle built for macOS, not iOS " \
      "(ios-arm64): the gem's package holds it, and its build did not replace it"
  end

  # On Android the library is an ELF shared object for each ABI, which
  # the NDK's clang, linking it directly with no flag of Fledge's,
  # aligns for 16 KB pages, as Google Play requires.
  def test_a_library_for_ffi_a_rakefile_links_is_found_for_each_android_abi_aligned_for_16_kb_pages
    runtimes = real_runtimes("android")
    ndk = android_ndk
    gem = rake_gem("thing", THING_RAKEFILE, files: { "thing.c" => "int thing(void) { return 1; }\n" })

    built = compile(runtimes, android, { gem => Fledge::PathPackage.new(gem) }, files: true)

    readelf = File.join(ndk.bin, "llvm-readelf")
    machines = built.targets.to_h do |name, target|
      library = target.ffi_libraries.fetch(0)
      assert_equal ["ext/libthing.so", ["app/vendor/cache/thing/ext/libthing.so"]], [library.file, library.links]
      read = Open3.capture2(readelf, "-h", "-lW", library.path).first
      alignments = read.lines.grep(/\A\s*LOAD\s/).map { |line| Integer(line.split.last) }
      assert_operator alignments.min, :>=, 16_384, "#{name}: aligned for 16 KB pages"
      [name, read[/Machine:\s+(.+)$/, 1]]
    end
    assert_equal({ "aarch64-linux-android" => "AArch64", "x86_64-linux-android" => "Advanced Micro Devices X86-64" }, machines)
  end

  # A library for ffi in C++, linked as ffi-compiler links one, with the
  # CXX it is given and no flag of Fledge's: the NDK's clang++ links the
  # shared C++ runtime, so the library holds none of its own to export,
  # and the app carries the NDK's libc++_shared.so for each ABI beside
  # it, as Gradle's plugin packs it for a CMake build with c++_shared.
  def test_a_cpp_library_for_ffi_carries_the_ndks_shared_cpp_runtime_into_android
    runtimes = real_runtimes("android")
    ndk = android_ndk
    gem = rake_gem("thing", <<~'RAKEFILE', files: { "thing.cpp" => %(#include <string>\nextern "C" int thing(void) { return std::to_string(42).size(); }\n) })
      task :default do
        sh "#{ENV.fetch('CXX')} -shared -fPIC -o libthing.so thing.cpp"
      end
    RAKEFILE

    built = compile(runtimes, android, { gem => Fledge::PathPackage.new(gem) }, files: true)
    project = File.join(@dir, "project")
    FileUtils.mkdir_p(ruby_root = File.join(project, "fledge"))
    libraries = Fledge::MobileProject::AndroidLibraries.new(built)
    libraries.call(project, ruby_root:)
    libraries.carry_cxx_runtime(project, ruby_root:)

    readelf = File.join(ndk.bin, "llvm-readelf")
    built.targets.each_value do |build|
      library = build.ffi_libraries.fetch(0).path
      assert_includes Open3.capture2(readelf, "--needed-libs", library).first, "libc++_shared.so", "#{build.target.name}: the shared C++ runtime"
      exported = Open3.capture2(readelf, "--dyn-syms", "-W", library).first.lines.reject { |line| line.include?(" UND ") }
      assert_empty exported.grep(/ (?:_ZNSt|_ZSt|__cxa_|__gxx_)/), "#{build.target.name}: exports no C++ runtime"
      assert_carries_stripped_cxx_runtime(ndk, project, build)
    end
    # Its license goes with it: the NDK's notice for the toolchain it
    # came from, after a header that names the files it covers.
    notice = File.read(File.join(ruby_root, "notices", "libc++_shared.txt"))
    assert_includes notice, "lib/arm64-v8a/libc++_shared.so and lib/x86_64/libc++_shared.so, among the app's native libraries"
    assert_includes notice, "#{File.basename(ndk.root)}, since a\nlibrary of the app's gems links it."
    assert notice.end_with?(File.read(File.join(ndk.bin, "..", "NOTICE"))), "the NDK's toolchain NOTICE, whole"
    assert_includes notice, "The libc++ library is dual licensed"
    linkage = Fledge::MobileProject::AndroidLinkage.new(readers: Fledge::Binary::Readers.llvm(ndk.bin))
    assert_empty linkage.problems(project, libraries.judged), "the shared C++ runtime the app carries counts"
  end

  # A library a gem's Rakefile links against one this computer has and
  # the app does not carry builds, and would fail when Ruby opens it on
  # the phone: the build reads what each library in the app needs, with
  # the NDK's own tools, and names it.
  def test_an_android_library_that_needs_one_the_app_does_not_carry_is_named
    runtimes = real_runtimes("android")
    ndk = android_ndk
    gem = rake_gem("thing", <<~'RAKEFILE', files: { "thing.c" => "int thing(void) { return 1; }\n" })
      require "tmpdir"
      task :default do
        elsewhere = Dir.mktmpdir
        sh "#{ENV.fetch('CC')} -shared -fPIC -o #{elsewhere}/libnowhere.so -x c /dev/null"
        sh "#{ENV.fetch('CC')} -shared -fPIC -o libthing.so thing.c -L#{elsewhere} -Wl,--no-as-needed -lnowhere"
      end
    RAKEFILE

    built = compile(runtimes, android, { gem => Fledge::PathPackage.new(gem) }, files: true)
    project = File.join(@dir, "project")
    FileUtils.mkdir_p(ruby_root = File.join(project, "fledge"))
    libraries = Fledge::MobileProject::AndroidLibraries.new(built)
    libraries.call(project, ruby_root:)
    linkage = Fledge::MobileProject::AndroidLinkage.new(readers: Fledge::Binary::Readers.llvm(ndk.bin))

    assert_equal [
"thing's ext/libthing.so needs libnowhere.so, which neither Android, nor Fledge's runtime, nor the app's own native " \
  "libraries provide, so the app could not load it on a phone. Build the gem so that it carries the library, or links it " \
  "statically.",
], linkage.problems(project, libraries.judged)
  end

  # What Android offers every app is the NDK's public libraries at the
  # runtime's API level, 26, whose stubs the NDK holds for each ABI, but
  # the system's own libc++.so, which no app may link
  # (Fledge::Linkage::SYSTEM_LIBRARIES).
  def test_the_libraries_android_offers_every_app_are_the_ndks_stubs_for_api_26
    ndk = android_ndk
    pattern = Fledge::Linkage::SYSTEM_LIBRARIES.fetch("android").first
    %w[aarch64-linux-android x86_64-linux-android].each do |triple|
      stubs = Dir.children(File.join(ndk.bin, "..", "sysroot", "usr", "lib", triple, "26")).grep(/\.so\z/).sort - ["libc++.so"]
      assert_equal stubs, stubs.grep(pattern), triple
      refute_match pattern, "libc++.so", triple
      assert_equal stubs.size, pattern.source.count("|") + 1, "#{triple}: one name in the pattern for each stub"
    end
  end

  # A Rakefile that compiles with this computer's own compiler, not the
  # phone's in CC, builds a library no phone loads: refused by name.
  def test_a_library_a_rakefile_builds_for_this_computer_is_refused_for_android
    runtimes = real_runtimes("android")
    android_ndk
    gem = rake_gem("thing", <<~RAKEFILE, files: { "thing.c" => "int thing(void) { return 1; }\n" })
      task :default do
        sh "cc -shared -fPIC -o libthing.so thing.c"
      end
    RAKEFILE

    error = assert_raises(Fledge::Error) { compile(runtimes, android, { gem => Fledge::PathPackage.new(gem) }, files: true) }

    assert_match(%r{thing 1\.0\.0's Rakefile built ext/libthing\.so for (?:Linux \S+|no Android system), not Android arm64-v8a \(aarch64-linux-android\)\.},
      error.message)
  end

  # Ruby's ffi takes Android for linux, so a library for a desktop's
  # Linux that a package holds, left as it was, is refused too.
  def test_a_linux_library_a_package_holds_and_its_rakefile_leaves_is_refused_for_android
    runtimes = real_runtimes("android")
    android_ndk
    skip "a library for a desktop's Linux is compiled on Linux" unless Fledge::Platform.local.os == "linux"
    gem = rake_gem("thing", "task :default\n",
      files: { "thing.c" => "int thing(void) { return 1; }\n", "x86_64-linux/libthing.so" => "" })
    folder = File.join(@dir, "gems", "thing", "ext")
    system("cc", "-shared", "-fPIC", "-o", File.join(folder, "x86_64-linux", "libthing.so"), File.join(folder, "thing.c"), exception: true)

    error = assert_raises(Fledge::Error) { compile(runtimes, android, { gem => Fledge::PathPackage.new(gem) }, files: true) }

    assert_match(%r{thing 1\.0\.0's Rakefile left ext/x86_64-linux/libthing\.so built for Linux \S+, not Android arm64-v8a}, error.message)
  end

  # A package may hold its library for ffi already built for each of
  # the phone's ABIs, which its Rakefile leaves as it was: each target
  # takes its own ABI's, read with the NDK's llvm-readelf, and carries
  # it as it carries one the Rakefile built.
  def test_the_libraries_a_package_holds_for_each_android_abi_are_libraries_for_ffi
    runtimes = real_runtimes("android")
    ndk = android_ndk
    gem = rake_gem("thing", "task :default\n",
      files: { "thing.c" => "int thing(void) { return 1; }\n", "aarch64-linux/libthing.so" => "", "x86_64-linux/libthing.so" => "" })
    folder = File.join(@dir, "gems", "thing", "ext")
    %w[aarch64 x86_64].each do |arch|
      system(File.join(ndk.bin, "#{arch}-linux-android26-clang"), "-shared", "-fPIC", "-o", File.join(folder, "#{arch}-linux", "libthing.so"),
        File.join(folder, "thing.c"), exception: true)
    end

    built = compile(runtimes, android, { gem => Fledge::PathPackage.new(gem) }, files: true)

    found = built.targets.transform_values { |target| target.ffi_libraries.map { |library| [library.file, library.links] } }
    assert_equal(%w[aarch64 x86_64].to_h do |arch|
      ["#{arch}-linux-android", [["ext/#{arch}-linux/libthing.so", ["app/vendor/cache/thing/ext/#{arch}-linux/libthing.so"]]]]
    end, found)
  end

  # A Rakefile requires the gems its gem depends on, as ffi-compiler's
  # require ffi, whose extension must be this computer's to load: the
  # build has each on its load path, compiled for this computer. This
  # one names its library by what the adder gem's C extension adds.
  def test_a_rakefile_requires_a_gem_its_gem_depends_on_compiled_for_this_computer
    runtimes = real_runtimes("android")
    android_ndk
    adder = File.expand_path("../../examples/native_phone/gems/adder", __dir__)
    gem = rake_gem("thing", <<~'RAKEFILE', files: { "thing.c" => "int thing(void) { return 1; }\n" }, dependencies: ["adder"])
      require "adder"
      task :default do
        sh "#{RbConfig::CONFIG['CC']} -shared -o lib#{Adder.add(2, 3)}.so thing.c"
      end
    RAKEFILE

    built = compile(runtimes, android, { gem => Fledge::PathPackage.new(gem) }, files: true,
      dependencies: { path_gem(adder) => Fledge::PathPackage.new(path_gem(adder)) })

    assert_equal({ "aarch64-linux-android" => ["ext/lib5.so"], "x86_64-linux-android" => ["ext/lib5.so"] },
      built.targets.transform_values { |target| target.ffi_libraries.map(&:file) })
  end

  # A Rakefile that links a library with the compiler in CC, as
  # ffi-compiler's tasks do.
  THING_RAKEFILE = <<~'RAKEFILE'
    task :default do
      sh "#{RbConfig::CONFIG['CC']} -c thing.c -o thing.o"
      sh "#{RbConfig::CONFIG['CC']} -shared -o libthing.so thing.o"
    end
  RAKEFILE

  # A Rakefile that builds nothing, as the mkrf_conf scripts that install
  # a gem's dependencies leave behind, makes no extension to link.
  def test_a_rakefile_that_builds_nothing_registers_nothing
    runtimes = real_runtimes("ios")
    gem = rake_gem("quiet", "task :default\n")

    built = compile(runtimes, ios, { gem => Fledge::PathPackage.new(gem) })

    assert_empty built.registrations
    assert_equal({ "ios-arm64" => [], "ios-arm64-simulator" => [] }, built.targets.transform_values(&:archives))
  end

  def test_fledge_build_ios_links_the_extensions_into_the_project
    runtimes = real_runtimes("ios")
    out = StringIO.new
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache"))
    status = Fledge::CLI::Build.new(out:, err:, env:).call(["ios", "-o", File.join(@dir, "dist"), File.expand_path("../../examples/native_phone", __dir__)])

    assert_equal 0, status, err.string
    project = File.join(@dir, "dist", "NativePhone-ios")
    assert_equal %w[Info.plist ios-arm64 ios-arm64-simulator], Dir.children(File.join(project, "FledgeExtensions.xcframework")).sort
    unit = File.read(File.join(project, "Host", "fledge_extensions.c"))
    assert_includes unit, 'fledge_ruby_add_extension("adder/adder", Init_fledge_0)'
    stub = File.join(project, "fledge", "app", "gems", "adder", "lib", "adder", "adder.rb")
    assert_equal Fledge::MobileExtensions::Stub.source("adder/adder"), File.read(stub), "lib/adder.rb's require_relative finds it"
    yml = File.read(File.join(project, "project.yml"))
    assert_includes yml, "- framework: FledgeExtensions.xcframework"
    assert_includes yml, 'OTHER_LDFLAGS: "$(inherited) -lc++"'
    marks = Dir.glob(File.join(project, "fledge", "lib", "ruby", "gems", "*", "**", "gem.build_complete"))
    assert_empty marks, "a path gem needs no mark, as on a desktop"
  end

  # examples/rust_phone's gem has a Rust extension, built with rb-sys and
  # magnus: rb_sys, which its extconf.rb requires, is found among the
  # app's gems, and Cargo builds a static library for each slice, whose
  # objects are for iOS and the Simulator, that keeps the Init function
  # rb-sys names and is registered under the extension's name. rb-sys's
  # Makefile installs the extension where mkmf's does, so the app has a
  # Ruby file at that path that requires it (Stub).
  def test_fledge_build_ios_links_a_rust_extension_built_for_each_slice
    runtimes = real_runtimes("ios")
    rust_targets("ios", %w[aarch64-apple-ios aarch64-apple-ios-sim])
    project = build_example("ios", "rust_phone", runtimes, "RustPhone-ios")

    stub = File.join(project, "fledge", "app", "gems", "rusty", "lib", "rusty", "rusty.rb")
    assert_equal Fledge::MobileExtensions::Stub.source("rusty/rusty"), File.read(stub), "a require_relative of the extension finds it"
    unit = File.read(File.join(project, "Host", "fledge_extensions.c"))
    assert_includes unit, 'fledge_ruby_add_extension("rusty/rusty", Init_rusty)'
    yml = File.read(File.join(project, "project.yml"))
    refute_includes yml, "-lc++", "the extension has no C++"
    refute_includes yml, "-lSystem", "every iOS program links libSystem already"
    platforms = %w[ios-arm64 ios-arm64-simulator].to_h do |slice|
      library = File.join(project, "FledgeExtensions.xcframework", slice, "libFledgeExtensions.a")
      assert_includes Open3.capture2("xcrun", "nm", "-g", library, err: File::NULL).first, " T _Init_rusty", slice
      loads = Open3.capture2("xcrun", "otool", "-l", library, err: File::NULL).first
      [slice, loads.scan(/^\s*platform (\d+)$/).flatten.uniq]
    end
    assert_equal({ "ios-arm64" => ["2"], "ios-arm64-simulator" => ["7"] }, platforms, "LC_BUILD_VERSION's platforms: 2 is iOS, 7 its Simulator")
  end

  # The same for each Android ABI: libfledgeext.so defines the Init
  # function, takes Ruby from the runtime's library, and is for the
  # ABI's processor.
  def test_fledge_build_android_links_a_rust_extension_built_for_each_abi
    runtimes = real_runtimes("android")
    ndk = android_ndk
    rust_targets("android", %w[aarch64-linux-android x86_64-linux-android])
    project = build_example("android", "rust_phone", runtimes, "RustPhone-android")

    stub = File.join(project, "fledge", "app", "gems", "rusty", "lib", "rusty", "rusty.rb")
    assert_equal Fledge::MobileExtensions::Stub.source("rusty/rusty"), File.read(stub), "a require_relative of the extension finds it"
    readelf = File.join(ndk.bin, "llvm-readelf")
    machines = { "arm64-v8a" => "AArch64", "x86_64" => "Advanced Micro Devices X86-64" }.to_h do |abi, machine|
      library = File.join(project, "src", "main", "jniLibs", abi, "libfledgeext.so")
      dynamic = Open3.capture2(readelf, "-d", "--dyn-syms", library).first
      refute_match(/UND\s+Init_rusty/, dynamic, "#{abi}: the extension is linked in")
      assert_includes dynamic, "Shared library: [libfledgeruby.so]", "#{abi}: Ruby is the runtime's"
      [abi, Open3.capture2(readelf, "-h", library).first[/Machine:\s+(.+)$/, 1] == machine]
    end
    assert_equal({ "arm64-v8a" => true, "x86_64" => true }, machines)
  end

  # fledge build android ships a C and C++ extension as a file: each
  # ABI's shared object is a native library of the package, which the
  # installer extracts, and fledge.links names the path in the app's
  # Ruby where a desktop has the file, which the runtime links to it as
  # the app starts. Nothing is linked into libfledgeext.so, which is
  # there all the same, for a host that names it, needing only Ruby's
  # library; no Ruby file stands at the extension's path, and Fledge's
  # own MainActivity loads nothing, since the runtime loads it.
  def test_fledge_build_android_ships_an_extension_as_a_native_library_linked_from_its_path
    runtimes = real_runtimes("android")
    ndk = android_ndk

    project = build_example("android", "native_phone", runtimes, "NativePhone-android")

    readelf = File.join(ndk.bin, "llvm-readelf")
    machines = { "arm64-v8a" => "AArch64", "x86_64" => "Advanced Micro Devices X86-64" }.to_h do |abi, machine|
      folder = File.join(project, "src", "main", "jniLibs", abi)
      linked, read = Open3.capture2(readelf, "-h", "--syms", File.join(folder, "libfledgeext.so"))
      assert_predicate read, :success?, "#{abi}: libfledgeext.so is there, for a host that names it"
      assert_match(/Type:\s+DYN/, linked, "#{abi}: libfledgeext.so is a shared library")
      refute_match(/Init_/, linked, "#{abi}: nothing is linked into libfledgeext.so")
      library = File.join(folder, "libfledgeext.adder.adder.so")
      dynamic = Open3.capture2(readelf, "-h", "-d", "--dyn-syms", library).first
      assert_match(/ Init_adder$/, dynamic, "#{abi}: the extension keeps its Init function")
      [abi, dynamic[/Machine:\s+(.+)$/, 1] == machine]
    end
    assert_equal({ "arm64-v8a" => true, "x86_64" => true }, machines)
    assert_equal "arm64-v8a\tlibfledgeext.adder.adder.so\tapp/gems/adder/lib/adder/adder.so\n" \
      "x86_64\tlibfledgeext.adder.adder.so\tapp/gems/adder/lib/adder/adder.so\n",
      File.readlines(File.join(project, "fledge", "fledge.links")).grep(/\tlibfledgeext\./).join,
      "the extension's links, beside those of the gems' commands"
    refute_path_exists File.join(project, "fledge", "app", "gems", "adder", "lib", "adder", "adder.rb")
    activity = File.read(File.join(project, "src", "main", "java", "org", "setdef", "fledge", "host", "MainActivity.java"))
    refute_includes activity, "loadLibrary"
  end

  # examples/ffi_library_phone's gems, llhttp-ffi and scrypt from
  # rubygems.org, each build a library for ffi from a Rakefile, with
  # ffi-compiler and ffi compiled for this computer: each library is a
  # native library of the app's own in each ABI, built for that ABI,
  # stripped, and aligned for 16 KB pages, linked from the path in the
  # gem where ffi-compiler's loader looks for it.
  def test_fledge_build_android_ships_the_libraries_for_ffi_that_rakefiles_build
    runtimes = real_runtimes("android")
    ndk = android_ndk

    project = build_example("android", "ffi_library_phone", runtimes, "FfiLibraryPhone-android")

    readelf = File.join(ndk.bin, "llvm-readelf")
    names = %w[libfledgeffi.llhttp-ffi.ext.ARCH-linux.libllhttp-ext.so libfledgeffi.scrypt.ext.scrypt.ARCH-linux.libscrypt_ext.so]
    machines = { "arm64-v8a" => "aarch64", "x86_64" => "x86_64" }.to_h do |abi, arch|
      read = names.map do |name|
        library = File.join(project, "src", "main", "jniLibs", abi, name.sub("ARCH", arch))
        elf = Open3.capture2(readelf, "-h", "-lW", "-S", library).first
        alignments = elf.lines.grep(/\A\s*LOAD\s/).map { |line| Integer(line.split.last) }
        assert_operator alignments.min, :>=, 16_384, "#{abi}: #{name} aligned for 16 KB pages"
        refute_match(/\.symtab/, elf, "#{abi}: #{name} stripped")
        elf[/Machine:\s+(.+)$/, 1]
      end
      [abi, read.uniq]
    end
    assert_equal({ "arm64-v8a" => ["AArch64"], "x86_64" => ["Advanced Micro Devices X86-64"] }, machines)
    # The ffi gem's own extension is a file too, with lines of its own.
    links = File.readlines(File.join(project, "fledge", "fledge.links")).map { |line| line.chomp.split("\t") }
      .select { |_, name, _| name.start_with?("libfledgeffi.") }
    gems = %r{\Alib/ruby/gems/[^/]+/gems/}
    assert_equal [
      ["arm64-v8a", "libfledgeffi.llhttp-ffi.ext.aarch64-linux.libllhttp-ext.so", "llhttp-ffi-0.5.1/ext/aarch64-linux/libllhttp-ext.so"],
      ["arm64-v8a", "libfledgeffi.scrypt.ext.scrypt.aarch64-linux.libscrypt_ext.so", "scrypt-3.1.0/ext/scrypt/aarch64-linux/libscrypt_ext.so"],
      ["x86_64", "libfledgeffi.llhttp-ffi.ext.x86_64-linux.libllhttp-ext.so", "llhttp-ffi-0.5.1/ext/x86_64-linux/libllhttp-ext.so"],
      ["x86_64", "libfledgeffi.scrypt.ext.scrypt.x86_64-linux.libscrypt_ext.so", "scrypt-3.1.0/ext/scrypt/x86_64-linux/libscrypt_ext.so"],
    ], links.map { |abi, name, path| [abi, name, path.sub(gems, "")] }
    assert(links.all? { |_, _, path| path.match?(gems) }, links.inspect)
    # Their libraries are C, so the app carries no C++ runtime and no
    # notice of one.
    assert_empty Dir.glob(File.join(project, "src", "main", "jniLibs", "*", "libc++_shared.so"))
    refute_path_exists File.join(project, "fledge", "notices", "libc++_shared.txt")
  end

  # On iOS, examples/ffi_library_phone's two libraries, llhttp-ffi's and
  # scrypt's, are each a framework of its own, a dynamic library for
  # each slice whose install name is the framework's, which the project
  # embeds and does not link, and a link at the path where ffi-compiler's
  # loader looks for it leads to the framework in the built app. The
  # library and the object files llhttp-ffi's package holds, which its
  # author built on a Mac, are not in the app.
  def test_fledge_build_ios_embeds_each_library_for_ffi_that_a_rakefile_builds_as_a_framework
    runtimes = real_runtimes("ios")

    project = build_example("ios", "ffi_library_phone", runtimes, "FfiLibraryPhone-ios")

    names = %w[fledgeffi.llhttp-ffi.ext.aarch64-darwin.libllhttp-ext.bundle fledgeffi.scrypt.ext.scrypt.aarch64-darwin.libscrypt-ext.bundle]
    names.each do |name|
      read = { "ios-arm64" => "IOS", "ios-arm64-simulator" => "IOSSIMULATOR" }.map do |slice, platform|
        binary = File.join(project, "Frameworks", "#{name}.xcframework", slice, "#{name}.framework", name)
        kind = Open3.capture2("xcrun", "otool", "-hv", binary).first.lines.last.split[4]
        built = Open3.capture2("xcrun", "vtool", "-show-build", binary).first[/platform (\S+)/, 1]
        id = Open3.capture2("xcrun", "otool", "-D", binary).first.lines.last.strip
        info = JSON.parse(Open3.capture2("plutil", "-convert", "json", "-o", "-", File.join(File.dirname(binary), "Info.plist")).first)
        [kind, built == platform, id, info.values_at("CFBundleExecutable", "CFBundlePackageType")]
      end
      assert_equal [["DYLIB", true, "@rpath/#{name}.framework/#{name}", [name, "FMWK"]]] * 2, read, name
    end
    root = File.join(project, "fledge")
    installed = Dir.glob(File.join(root, "lib", "ruby", "gems", "*", "gems")).first.to_s
    {
      "llhttp-ffi-0.5.1/ext/aarch64-darwin/libllhttp-ext.bundle" => names[0],
      "scrypt-3.1.0/ext/scrypt/aarch64-darwin/libscrypt_ext.bundle" => names[1],
    }.each do |path, name|
      at = File.join(installed, path)
      assert_equal "/App.app/Frameworks/#{name}.framework/#{name}",
        File.expand_path(File.readlink(at), File.dirname(at).sub(root, "/App.app/fledge")), path
    end
    refute_path_exists File.join(installed, "llhttp-ffi-0.5.1", "ext", "aarch64-darwin", "llhttp", "api.o")
    assert_empty(Dir.glob("**/*", base: root).select { |path| Fledge::MobileProject::IOS.mach_o?(File.join(root, path)) })
    spec = File.read(File.join(project, "project.yml"))
    names.each { |name| assert_includes spec, "- framework: Frameworks/#{name}.xcframework\n        embed: true\n        link: false" }
  end

  # Writes examples/+name+'s project for +phone+ with fledge build, from
  # the runtimes in +runtimes+, and returns the project's folder, named
  # +project+.
  def build_example(phone, name, runtimes, project)
    out = StringIO.new
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache"))
    status = Fledge::CLI::Build.new(out:, err:, env:).call([phone, "-o", File.join(@dir, "dist"), File.expand_path("../../examples/#{name}", __dir__)])

    assert_equal 0, status, err.string
    File.join(@dir, "dist", project)
  end

  # Skips unless this computer's Rust has the standard library of each
  # of +targets+, the Rust targets of the phone +name+, as rustup target
  # add installs it.
  def rust_targets(name, targets)
    targets.each do |target|
      Fledge::MobileExtensions::Rust.check(target, gem: "examples/rust_phone's rusty", env: ENV.to_h)
    rescue Fledge::Error => e
      missing(name, e.message)
    end
  end

  # Asserts that +project+'s jniLibs folder for +build+'s ABI holds the
  # NDK's own libc++_shared.so for that ABI, stripped as llvm-strip
  # --strip-unneeded strips it, as every other library placed there is.
  def assert_carries_stripped_cxx_runtime(ndk, project, build)
    runtime = File.join(ndk.bin, "..", "sysroot", "usr", "lib", build.target.name, "libc++_shared.so")
    carried = File.join(project, "src", "main", "jniLibs", build.target.abi, "libc++_shared.so")
    assert_path_exists carried, "#{build.target.name}: libc++_shared.so in jniLibs"
    stripped = File.join(@dir, "stripped-#{build.target.abi}.so")
    FileUtils.cp(runtime, stripped)
    assert system(File.join(ndk.bin, "llvm-strip"), "--strip-unneeded", stripped), "llvm-strip strips #{runtime}"
    assert_operator File.size(stripped), :<, File.size(runtime), "#{build.target.name}: the NDK's runtime has what stripping leaves out"
    assert_equal File.binread(stripped), File.binread(carried), "#{build.target.name}: the NDK's own, for its ABI, stripped"
  end

  def tally_gem
    folder = File.expand_path("../../examples/cmake_phone/gems/tally", __dir__)
    Fledge::PathGem.new(name: "tally", version: "1.0.0", folder:, app_path: "vendor/cache/tally", glob: "{,*,*/*}.gemspec", inside: true)
  end

  def rakesum_gem
    folder = File.expand_path("../fixtures/rakesum", __dir__)
    Fledge::PathGem.new(name: "rakesum", version: "1.0.0", folder:, app_path: "vendor/cache/rakesum", glob: "{,*,*/*}.gemspec", inside: true)
  end

  # A path gem +name+ whose gemspec names ext/NAME/extconf.rb, with
  # +extconf+ and +files+ in ext/NAME/.
  def extconf_gem(name, extconf, files = {})
    folder = File.join(@dir, "gems", name)
    FileUtils.mkdir_p(File.join(folder, "ext", name))
    File.write(File.join(folder, "ext", name, "extconf.rb"), extconf)
    files.each { |file, text| File.write(File.join(folder, "ext", name, file), text) }
    File.write(File.join(folder, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = "1.0.0"
        spec.authors = ["Kerrick Long"]
        spec.summary = "An extconf.rb's extension"
        spec.files = #{(["ext/#{name}/extconf.rb"] + files.keys.map { |file| "ext/#{name}/#{file}" }).inspect}
        spec.extensions = ["ext/#{name}/extconf.rb"]
      end
    RUBY
    Fledge::PathGem.new(name:, version: "1.0.0", folder:, app_path: "vendor/cache/#{name}", glob: "{,*,*/*}.gemspec", inside: true)
  end

  # A path gem +name+ whose gemspec names ext/Rakefile, with +rakefile+
  # and +files+ in ext/, which depends on the gems +dependencies+ names.
  def rake_gem(name, rakefile, files: {}, dependencies: [])
    folder = File.join(@dir, "gems", name)
    FileUtils.mkdir_p(File.join(folder, "ext"))
    File.write(File.join(folder, "ext", "Rakefile"), rakefile)
    files.each do |file, text|
      FileUtils.mkdir_p(File.dirname(File.join(folder, "ext", file)))
      File.write(File.join(folder, "ext", file), text)
    end
    File.write(File.join(folder, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = "1.0.0"
        spec.authors = ["Kerrick Long"]
        spec.summary = "A Rakefile's extension"
        spec.files = #{(['ext/Rakefile'] + files.keys.map { |file| "ext/#{file}" }).inspect}
        spec.extensions = ["ext/Rakefile"]
        #{dependencies.map { |dependency| "spec.add_dependency #{dependency.inspect}" }.join("\n")}
      end
    RUBY
    Fledge::PathGem.new(name:, version: "1.0.0", folder:, app_path: "vendor/cache/#{name}", glob: "{,*,*/*}.gemspec", inside: true)
  end

  # The NDK where this computer has one; the test skips without it
  # (AndroidRequired).
  def android_ndk
    Fledge::MobileExtensions::NDK.find(ENV, host: Fledge::Platform.local)
  rescue Fledge::Error => e
    android_missing(e.message)
  end

  # Skips for want of what a test of the phone +name+ needs, or fails
  # where FLEDGE_REQUIRE_ANDROID or FLEDGE_REQUIRE_IOS asks
  # (AndroidRequired, IOSRequired).
  def missing(name, message)
    (name == "android") ? android_missing(message) : ios_missing(message)
  end

  def cmake?
    system("cmake", "--version", out: File::NULL, err: File::NULL) || false
  end

  def real_runtimes(name)
    missing(name, "Xcode builds the iOS slices on a Mac only") unless Fledge::Platform.local.name == "arm64-darwin" || name != "ios"
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    phone = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(name)))
    missing(name, "no #{File.basename(phone)} in #{dir}; run bundle exec rake runtime[#{name}]") unless File.file?(phone)
    dir
  end

  def path_gem(folder)
    Fledge::PathGem.new(name: "adder", version: "1.0.0", folder:, app_path: "vendor/cache/adder", glob: "{,*,*/*}.gemspec", inside: true)
  end

  # The probe gem's extension, compiled for +phone+ where the folder the
  # runtime's build gave Ruby's configure for libffi holds a libffi, as
  # on the computer that built the runtime: +library+, named +name+,
  # defines ffi_prep_closure_loc for the phone. The libffi folder each
  # rbconfig.rb records is moved to that one. With +own+, the gem's build
  # names that folder itself (--with-ffi-dir).
  def flags_with_the_runtime_builders_libffi(runtimes, phone, name, library, own: false)
    libffi = File.join(@dir, "built", "libffi")
    FileUtils.mkdir_p([File.join(libffi, "include"), File.join(libffi, "lib")])
    File.write(File.join(libffi, "include", "ffi.h"), "int ffi_prep_closure_loc(void);\n")
    File.write(File.join(libffi, "lib", name), library)
    gem = extconf_gem("probe", <<~RUBY, "probe.c" => "#include <ruby.h>\nvoid Init_probe(void) { rb_define_module(\"Probe\"); }\n")
      require "mkmf"
      dir_config("ffi")
      have_header("ffi.h") && have_library("ffi", "ffi_prep_closure_loc", ["ffi.h"])
      create_makefile("probe/probe")
    RUBY
    build_args = own ? { "probe" => ["--with-ffi-dir=#{libffi}"] } : {}
    built = compile(runtimes, phone, { gem => Fledge::PathPackage.new(gem) }, build_args:) do |root|
      Dir.glob(File.join(root, "**", "rbconfig.rb")).each do |rbconfig|
        text = File.read(rbconfig)
        recorded = text[/--with-libffi-dir=([^' ]+)/, 1] or flunk "#{rbconfig} records no libffi folder"
        File.write(rbconfig, text.gsub(recorded, libffi))
      end
    end
    built.targets.transform_values(&:flags)
  end

  def compile(runtimes_dir, phone, packages, build_args: {}, files: false, dependencies: {})
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes_dir)
    runtimes = Fledge::Runtimes.new(env:)
    tree = File.join(@dir, "tree")
    Fledge::Archive.unpack(runtimes.archive(phone), into: tree)
    root = File.join(tree, Dir.children(tree).first)
    yield root if block_given?
    log = StringIO.new
    Fledge::MobileExtensions.new(platform: phone, packages:, build_args:, host: Fledge::Platform.local, runtimes:,
      work: File.join(@dir, "work"), log:, gem_dir: "lib/ruby/gems/4.1.0+5", env:, files:, dependencies:).call(root)
  rescue Fledge::Error => e
    raise Fledge::Error, "#{e.message}\n#{log&.string}"
  end
end
