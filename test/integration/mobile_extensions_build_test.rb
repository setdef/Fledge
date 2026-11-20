# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "stringio"

# Native gems on phones (doc/contributors/design/phone-projects.md,
# "Gems with extensions"), compiled for real: a gem's extension for
# every target of a phone, with the real mobile runtimes and tools
# where this computer has them. test/mobile_extensions_test.rb covers
# which extensions Fledge compiles and how it writes what links them.
class MobileExtensionsBuildTest < Minitest::Test
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
  # Simulator) job has both, and builds examples/native_phone with fledge
  # build ios, compiles it with Xcode for both slices, and runs it.
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
  # has already loaded, for Ruby's C API. It carries the C++ runtime it
  # needs, since the package has no libc++_shared.so; finds a library it
  # links beside itself; and aligns its LOAD segments for 16 KB pages.
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
      refute_includes dynamic, "libc++_shared.so", "#{name}: the C++ runtime is linked in statically"
      assert_match(/\(RUNPATH\)\s+Library runpath: \[\$ORIGIN\]/, dynamic, "#{name}: what it links is found beside it")
      alignments = dynamic.lines.grep(/\A\s*LOAD\s/).map { |line| Integer(line.split.last) }
      assert_operator alignments.min, :>=, 16_384, "#{name}: aligned for 16 KB pages"
      [name, Open3.capture2(readelf, "-h", library.path).first[/Machine:\s+(.+)$/, 1]]
    end
    assert_equal({ "aarch64-linux-android" => "AArch64", "x86_64-linux-android" => "Advanced Micro Devices X86-64" }, machines)
  end

  # A C extension over a C++ library names a desktop's C++ runtime
  # (-lstdc++), which the NDK links as libc++_shared.so; built as a file,
  # it links the C++ runtime in instead, as libfledgeext.so does.
  def test_an_android_c_extension_over_a_cpp_library_built_as_a_file_carries_its_cpp_runtime
    runtimes = real_runtimes("android")
    skip "examples/cmake_phone needs CMake on the PATH" unless cmake?
    ndk = android_ndk

    built = compile(runtimes, android, { tally_gem => Fledge::PathPackage.new(tally_gem) }, files: true)

    readelf = File.join(ndk.bin, "llvm-readelf")
    built.targets.each do |name, target|
      dynamic = Open3.capture2(readelf, "-d", "--dyn-syms", target.libraries.fetch(0).path).first
      refute_includes dynamic, "libc++_shared.so", "#{name}: the C++ runtime is linked in statically"
      refute_match(/UND\s+(?:_ZNSt|_Znwm|_ZdlPv|__gxx_personality)/, dynamic, "#{name}: the C++ runtime is linked in")
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
    skip "examples/cmake_phone needs CMake on the PATH" unless cmake?
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
  # one: libfledgeext.so holds the library's code, and needs no C++
  # runtime the package does not carry.
  def test_a_cmake_library_an_extconf_builds_is_linked_for_each_android_abi
    runtimes = real_runtimes("android")
    skip "examples/cmake_phone needs CMake on the PATH" unless cmake?
    ndk = begin
      Fledge::MobileExtensions::NDK.find(ENV, host: Fledge::Platform.local)
    rescue Fledge::Error => e
      skip e.message
    end
    built = compile(runtimes, android, { tally_gem => Fledge::PathPackage.new(tally_gem) })
    registration = File.join(@dir, "registration.c")
    File.write(registration, Fledge::MobileExtensions.registration_source(built.registrations))
    compiler = Fledge::MobileExtensions.new(platform: android, packages: {}, build_args: {}, host: Fledge::Platform.local,
      runtimes: Fledge::Runtimes.new(env: ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes)), work: File.join(@dir, "work"), log: StringIO.new,
      gem_dir: "lib/ruby/gems/4.1.0+5")
    machines = built.targets.to_h do |name, build|
      library = compiler.shared_library(built, build, registration:, into: File.join(@dir, name, "libfledgeext.so"))
      readelf = File.join(ndk.bin, "llvm-readelf")
      dynamic = Open3.capture2(readelf, "-d", "--dyn-syms", library).first
      refute_match(/UND\s+tally_/, dynamic, "#{name}: the library's code is linked in")
      refute_includes dynamic, "libc++_shared.so", "#{name}: the C++ runtime is linked in statically"
      refute_match(/UND\s+(?:_ZNSt|_Znwm|_ZdlPv|__gxx_personality)/, dynamic, "#{name}: the C++ runtime is linked in")
      assert_match(/\(RUNPATH\)\s+Library runpath: \[\$ORIGIN\]/, dynamic, "#{name}: the ruby program finds what it needs beside it")
      [name, Open3.capture2(readelf, "-h", library).first[/Machine:\s+(.+)$/, 1]]
    end
    assert_equal({ "aarch64-linux-android" => "AArch64", "x86_64-linux-android" => "Advanced Micro Devices X86-64" }, machines)
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
  # and the path in the app where the gem looks for it. The iOS project
  # then refuses it (test/mobile_build_test.rb).
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
    Fledge::MobileProject::AndroidLibraries.new(built).call(project, ruby_root:)

    readelf = File.join(ndk.bin, "llvm-readelf")
    built.targets.each_value do |build|
      library = build.ffi_libraries.fetch(0).path
      assert_includes Open3.capture2(readelf, "--needed-libs", library).first, "libc++_shared.so", "#{build.target.name}: the shared C++ runtime"
      exported = Open3.capture2(readelf, "--dyn-syms", "-W", library).first.lines.reject { |line| line.include?(" UND ") }
      assert_empty exported.grep(/ (?:_ZNSt|_ZSt|__cxa_|__gxx_)/), "#{build.target.name}: exports no C++ runtime"
      runtime = File.join(ndk.bin, "..", "sysroot", "usr", "lib", build.target.name, "libc++_shared.so")
      carried = File.join(project, "src", "main", "jniLibs", build.target.abi, "libc++_shared.so")
      assert_path_exists carried, "#{build.target.name}: libc++_shared.so in jniLibs"
      assert_equal File.binread(runtime), File.binread(carried), "#{build.target.name}: the NDK's own, for its ABI"
    end
    # Its license goes with it: the NDK's notice for the toolchain it
    # came from, after a header that names the files it covers.
    notice = File.read(File.join(ruby_root, "notices", "libc++_shared.txt"))
    assert_includes notice, "lib/arm64-v8a/libc++_shared.so and lib/x86_64/libc++_shared.so, among the app's native libraries"
    assert_includes notice, "#{File.basename(ndk.root)}, since a\nlibrary of the app's gems links it."
    assert notice.end_with?(File.read(File.join(ndk.bin, "..", "NOTICE"))), "the NDK's toolchain NOTICE, whole"
    assert_includes notice, "The libc++ library is dual licensed"
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
    rust_targets(%w[aarch64-apple-ios aarch64-apple-ios-sim])
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
    ndk = begin
      Fledge::MobileExtensions::NDK.find(ENV, host: Fledge::Platform.local)
    rescue Fledge::Error => e
      skip e.message
    end
    rust_targets(%w[aarch64-linux-android x86_64-linux-android])
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
      File.read(File.join(project, "fledge", "fledge.links"))
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

  # Fledge does not yet put a library for ffi in an iOS app, where it
  # must be a framework of its own, so fledge build ios refuses
  # examples/ffi_library_phone, naming the first gem whose Rakefile built
  # one, and writes no project.
  def test_fledge_build_ios_refuses_a_library_for_ffi_that_a_rakefile_builds
    runtimes = real_runtimes("ios")
    out = StringIO.new
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache"))
    status = Fledge::CLI::Build.new(out:, err:, env:)
      .call(["ios", "-o", File.join(@dir, "dist"), File.expand_path("../../examples/ffi_library_phone", __dir__)])

    refute_equal 0, status
    assert_includes err.string, "fledge build: llhttp-ffi's Rakefile built ext/aarch64-darwin/libllhttp-ext.bundle, a library for " \
      "Ruby's ffi to load, and Fledge does not yet put such a library in an iOS app, where it must be a framework of its own."
    refute_path_exists File.join(@dir, "dist", "FfiLibraryPhone-ios")
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
  # of +targets+, as rustup target add installs it.
  def rust_targets(targets)
    targets.each do |target|
      Fledge::MobileExtensions::Rust.check(target, gem: "examples/rust_phone's rusty", env: ENV.to_h)
    rescue Fledge::Error => e
      skip e.message
    end
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

  # The NDK where this computer has one; the test skips without it.
  def android_ndk
    Fledge::MobileExtensions::NDK.find(ENV, host: Fledge::Platform.local)
  rescue Fledge::Error => e
    skip e.message
  end

  def cmake?
    system("cmake", "--version", out: File::NULL, err: File::NULL) || false
  end

  def real_runtimes(name)
    skip "Xcode builds the iOS slices on a Mac only" unless Fledge::Platform.local.name == "arm64-darwin" || name != "ios"
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    phone = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(name)))
    skip "no #{File.basename(phone)} in #{dir}; run bundle exec rake runtime[#{name}]" unless File.file?(phone)
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
