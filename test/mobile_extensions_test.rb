# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"
require "open3"
require "stringio"

# Native gems on phones (ADR 022): which extensions Fledge compiles, how
# the registration unit and the link flags are written, where an Android
# NDK is found, and, with the real mobile runtimes and tools where this
# computer has them, a real gem compiled for every target of a phone.
class MobileExtensionsTest < Minitest::Test
  # The folder by its long names, as Dir.glob names what it finds in it
  # (Fledge::LongPath), where Windows' TMP names it by an 8.3 name.
  def setup
    @dir = Fledge::LongPath.of(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def native_gem(name: "native", extensions: ["ext/native/extconf.rb"], dependencies: {}, files: nil)
    files ||= extensions.to_h { |path| [path, "# #{path}\n"] }.merge("lib/#{name}.rb" => "")
    gem = FakeGem.build(@dir, name, "1.0.0", extensions:, files:, dependencies:)
    [
      Fledge::LockedGem.new(name:, version: "1.0.0", platform: "ruby", remote: "https://rubygems.org/", sha256: nil, credentials: nil),
      Fledge::GemPackage.new(gem.path),
]
  end

  def ios = Fledge::MobilePlatform.find("ios")
  def android = Fledge::MobilePlatform.find("android")

  def test_an_extconf_extension_is_one_fledge_compiles
    gem, package = native_gem

    assert_empty Fledge::MobileExtensions.problems(gem, package, ios, Fledge::Platform.find("arm64-darwin"))
    assert_empty Fledge::MobileExtensions.problems(gem, package, android, Fledge::Platform.find("x86_64-linux"))
  end

  def test_any_other_way_to_build_an_extension_is_refused_by_gem_and_by_what_to_do
    %w[Rakefile CMakeLists.txt configure Cargo.toml ext/native/mkrf_conf.rb].each do |builder|
      gem, package = native_gem(extensions: [builder])

      problems = Fledge::MobileExtensions.problems(gem, package, ios, Fledge::Platform.find("arm64-darwin"))

      assert_equal 1, problems.size, builder
      assert_includes problems.first, "native 1.0.0 has an extension built by #{builder}"
      assert_includes problems.first, "extconf.rb"
      assert_includes problems.first, 'gem "native", platforms: [...]'
    end
  end

  def test_a_rust_extension_through_rb_sys_is_refused_as_rust
    gem, package = native_gem(name: "oxide", dependencies: { "rb_sys" => ">= 0" })

    problems = Fledge::MobileExtensions.problems(gem, package, ios, Fledge::Platform.find("arm64-darwin"))

    assert_includes problems.first, "oxide 1.0.0 is a Rust extension (it depends on rb_sys)"
    assert_includes problems.first, "Rust"
  end

  def test_android_extensions_are_compiled_on_a_mac_or_linux_not_on_windows
    gem, package = native_gem

    problems = Fledge::MobileExtensions.problems(gem, package, android, Fledge::Platform.find("x64-mingw-ucrt"))

    assert_includes problems.first, "native 1.0.0 has an extension to compile for android, and Fledge compiles those on a Mac or Linux"
  end

  def test_the_registration_unit_registers_each_extension_from_a_constructor
    source = Fledge::MobileExtensions.registration_source([["greeter/greeter", "Init_fledge_0"], ["racc-like/cparse", "Init_fledge_1"]])

    assert_includes source, "#include <fledge_ruby.h>"
    assert_includes source, "extern void Init_fledge_0(void);"
    assert_includes source, "extern void Init_fledge_1(void);"
    assert_match(/__attribute__\(\(constructor\)\)\s+static void\s+fledge_register_extensions\(void\)/, source)
    assert_includes source, 'fledge_ruby_add_extension("greeter/greeter", Init_fledge_0)'
    assert_includes source, 'fledge_ruby_add_extension("racc-like/cparse", Init_fledge_1)'
  end

  def test_a_feature_name_with_a_quote_cannot_break_out_of_the_registration_unit
    source = Fledge::MobileExtensions.registration_source([["a\"b\\c", "Init_fledge_0"]])

    assert_includes source, 'fledge_ruby_add_extension("a\\"b\\\\c", Init_fledge_0)'
  end

  # The gem's build folder is a folder of this computer, as in a real
  # build, so its relative paths resolve the same way on every system the
  # tests run on, Windows' drive letters included.
  def test_link_flags_keep_libraries_frameworks_and_the_gems_own_archives
    root = File.expand_path(@dir)
    flags = Fledge::MobileExtensions::Linking.link_flags("-lz -framework Security -L../vendor/lib ./libvendored.a -fno-common -lz -Wl,-rpath,. -lsqlite3",
      dir: File.join(root, "ext"))

    assert_equal ["-lz", "-Wl,-framework,Security", "-L#{File.join(root, 'vendor', 'lib')}", File.join(root, "ext", "libvendored.a"), "-lsqlite3"], flags
  end

  # SDL3's sdl3.pc names fifteen frameworks; each must stay a framework
  # once the flags of two extensions, or two slices, are merged.
  def test_each_framework_stays_whole_through_merging
    flags = Fledge::MobileExtensions::Linking.link_flags("-framework UIKit -Wl,-framework,Metal -weak_framework CoreHaptics -framework UIKit", dir: "/work")

    assert_equal ["-Wl,-framework,UIKit", "-Wl,-framework,Metal", "-Wl,-weak_framework,CoreHaptics"], flags
  end

  def report(archive, flags, cxx: false)
    Fledge::MobileExtensions::Report.new(feature: "x/x", init: "Init_fledge_0", archive:, flags:, cxx:)
  end

  # A static library an extconf.rb links, such as SDL3's libSDL3.a for one
  # iOS slice, is linked with that target's archives, never with the
  # flags every target of the project shares.
  def test_a_target_links_its_own_static_libraries_with_its_archives
    target = Fledge::MobileExtensions::Target.new(name: "ios-arm64", root: "/r", arch_dir: "/r/a", libdir: "/r", environment: {}, abi: nil)
    build = Fledge::MobileExtensions::Linking.target_build(target, [
      report("/w/x.a", ["/sdl/ios-arm64/lib/libSDL3.a", "-Wl,-framework,UIKit", "-lm"]),
      report("/w/y.a", ["-Wl,-framework,UIKit", "-lm"], cxx: true),
    ])

    assert_equal ["/w/x.a", "/sdl/ios-arm64/lib/libSDL3.a", "/w/y.a"], build.archives
    assert_equal ["-Wl,-framework,UIKit", "-lm"], build.flags
    assert build.cxx
  end

  # Android loads native code only from the libraries its package holds,
  # so a shared library an extension links from its own folders, such as
  # libSDL3.so, goes into the package beside libfledgeext.so; the NDK's
  # own libraries, which the system has, do not.
  def test_the_shared_libraries_an_extension_links_from_its_folders_are_found
    lib = File.join(@dir, "sdl", "lib")
    FileUtils.mkdir_p(lib)
    FileUtils.touch([File.join(lib, "libSDL3.so"), File.join(lib, "libSDL3.a")])

    assert_equal [File.join(lib, "libSDL3.so")], Fledge::MobileExtensions::Linking.shared_libraries(["-L#{lib}", "-lSDL3", "-llog", "-lm"])
    assert_empty Fledge::MobileExtensions::Linking.shared_libraries(["-llog", "-lm"])
  end

  def test_the_shared_libraries_an_extension_links_go_beside_its_library
    lib = File.join(@dir, "sdl", "lib")
    jni = File.join(@dir, "src", "main", "jniLibs", "x86_64")
    FileUtils.mkdir_p([lib, jni])
    File.write(File.join(lib, "libSDL3.so"), "ELF")

    copied = Fledge::MobileExtensions::Linking.carry_shared_libraries(["-L#{lib}", "-lSDL3", "-llog"], into: jni)

    assert_equal [File.join(jni, "libSDL3.so")], copied
    assert_equal "ELF", File.read(File.join(jni, "libSDL3.so"))
  end

  # A C extension over a C++ library names the C++ runtime as it must on
  # a desktop, -lc++ on a Mac and -lstdc++ on Linux. Neither is the
  # runtime a phone's link takes (on Android, -lc++ is libc++_shared.so,
  # which the package does not carry), so the name marks the extension
  # as C++ and Fledge links each phone's C++ runtime itself.
  def test_the_cpp_runtime_an_extconf_names_marks_its_extension_as_cpp
    assert_equal ["-lm"], Fledge::MobileExtensions::Linking.link_flags("-lc++ -lstdc++ -lm", dir: "/work")
    assert Fledge::MobileExtensions::Linking.cxx_runtime?("-lstdc++ -lm")
    assert Fledge::MobileExtensions::Linking.cxx_runtime?("/work/libtally.a -lc++")
    refute Fledge::MobileExtensions::Linking.cxx_runtime?("-lc++abi -lm /work/libc++.a")
  end

  # CMake reads a toolchain file from CMAKE_TOOLCHAIN_FILE in the
  # environment when a build folder is new (ADR 027): for an iOS slice,
  # CMake's own iOS support, aimed at the slice's SDK, processor, and
  # deployment target with Xcode's compilers.
  def test_an_ios_slice_toolchain_file_aims_cmake_at_the_slice
    text = Fledge::MobileExtensions::CMake.ios(triple: "arm64-apple-ios15.0-simulator", sysroot: "/Xcode/iPhoneSimulator.sdk",
      cc: "/Xcode/clang", cxx: "/Xcode/clang++")

    assert_includes text, "set(CMAKE_SYSTEM_NAME iOS)"
    assert_includes text, 'set(CMAKE_OSX_SYSROOT "/Xcode/iPhoneSimulator.sdk")'
    assert_includes text, "set(CMAKE_OSX_ARCHITECTURES arm64)"
    assert_includes text, "set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)"
    assert_includes text, 'set(CMAKE_C_COMPILER "/Xcode/clang")'
    assert_includes text, 'set(CMAKE_CXX_COMPILER "/Xcode/clang++")'
    assert_includes text, 'set(CMAKE_OBJC_COMPILER "/Xcode/clang")'
    assert_includes text, 'set(CMAKE_OBJCXX_COMPILER "/Xcode/clang++")'
  end

  def test_a_triple_that_is_not_ios_has_no_ios_toolchain_file
    error = assert_raises(Fledge::Error) { Fledge::MobileExtensions::CMake.ios(triple: "arm64-apple-macos11", sysroot: "/s", cc: "cc", cxx: "c++") }

    assert_includes error.message, "arm64-apple-macos11"
  end

  # For an Android ABI, the NDK's own toolchain file, given the ABI and
  # the API level the runtime was built for, as Gradle gives it.
  def test_an_android_toolchain_file_takes_the_ndks_with_the_abi_and_api_level
    text = Fledge::MobileExtensions::CMake.android(ndk: "/sdk/ndk/30", abi: "x86_64", compiler: "x86_64-linux-android26-clang")

    assert_includes text, "set(ANDROID_ABI x86_64)"
    assert_includes text, "set(ANDROID_PLATFORM android-26)"
    assert_includes text, 'include("/sdk/ndk/30/build/cmake/android.toolchain.cmake")'
  end

  def test_a_path_in_a_toolchain_file_stays_one_cmake_string
    text = Fledge::MobileExtensions::CMake.android(ndk: '/my "ndk" $HOME\\x', abi: "x86_64", compiler: "x86_64-linux-android26-clang")

    assert_includes text, 'include("/my \\"ndk\\" \\$HOME\\\\x/build/cmake/android.toolchain.cmake")'
  end

  # The variables CMake reads from the environment that would aim it at
  # this computer instead of the phone, or give it this computer's
  # flags, are not passed to an extconf.rb.
  def test_cmakes_own_variables_for_this_computer_do_not_reach_an_extconf
    %w[CMAKE_OSX_ARCHITECTURES OBJC OBJCXX OBJCFLAGS OBJCXXFLAGS CC CXX CFLAGS LDFLAGS SDKROOT].each do |name|
      assert_includes Fledge::MobileExtensions::FOREIGN, name
    end
  end

  def test_the_ndk_is_found_where_android_tools_keep_it
    sdk = File.join(@dir, "sdk")
    %w[27.3.13750724 30.0.14904198].each do |version|
      FileUtils.mkdir_p(File.join(sdk, "ndk", version, "toolchains", "llvm", "prebuilt", "linux-x86_64", "bin"))
      File.write(File.join(sdk, "ndk", version, "source.properties"), "Pkg.Revision = #{version}\n")
    end
    explicit = File.join(@dir, "r28")
    FileUtils.mkdir_p(File.join(explicit, "toolchains", "llvm", "prebuilt", "linux-x86_64", "bin"))

    assert_equal File.join(sdk, "ndk", "30.0.14904198"),
      Fledge::MobileExtensions::NDK.find({ "ANDROID_HOME" => sdk }, host: Fledge::Platform.find("x86_64-linux")).root
    assert_equal explicit, Fledge::MobileExtensions::NDK.find({ "ANDROID_NDK_ROOT" => explicit, "ANDROID_HOME" => sdk }, host: Fledge::Platform.find("x86_64-linux")).root
    assert_equal File.join(explicit, "toolchains", "llvm", "prebuilt", "linux-x86_64", "bin"),
      Fledge::MobileExtensions::NDK.new(explicit, host: Fledge::Platform.find("x86_64-linux")).bin
  end

  def test_a_missing_ndk_says_what_to_install_and_where_it_looked
    error = assert_raises(Fledge::Error) { Fledge::MobileExtensions::NDK.find({ "HOME" => @dir }, host: Fledge::Platform.find("x86_64-linux")) }

    assert_includes error.message, "needs the Android NDK"
    assert_includes error.message, "ANDROID_NDK_ROOT"
    assert_includes error.message, "sdkmanager"
  end

  def test_a_gem_without_extensions_asks_for_no_compiler
    gem, package = native_gem(extensions: [], files: { "lib/pure.rb" => "" })

    assert_empty Fledge::MobileExtensions.problems(gem, package, ios, Fledge::Platform.find("arm64-darwin"))
  end

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
    greeter = File.expand_path("../examples/native_phone/gems/adder", __dir__)
    spec_package = Fledge::PathPackage.new(path_gem(greeter))
    built = compile(runtimes, ios, { path_gem(greeter) => spec_package })

    assert_equal [["adder/adder", "Init_fledge_0"]], built.registrations
    assert_equal %w[ios-arm64 ios-arm64-simulator], built.targets.keys
    platforms = built.targets.transform_values do |target|
      archive = target.archives.fetch(0)
      assert_includes Open3.capture2("xcrun", "nm", archive).first, " T _Init_fledge_0"
      object = Dir.glob(File.join(File.dirname(archive), "*.o")).first.to_s
      Open3.capture2("xcrun", "vtool", "-show-build", object).first[/platform (\S+)/, 1]
    end
    assert_equal({ "ios-arm64" => "IOS", "ios-arm64-simulator" => "IOSSIMULATOR" }, platforms)
  end

  # examples/cmake_phone's extconf.rb runs CMake, which builds its C++
  # library from CMAKE_TOOLCHAIN_FILE for each slice (ADR 027): the
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
      runtimes: Fledge::Runtimes.new(env: ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes)), work: File.join(@dir, "work"), log: StringIO.new)
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

  def tally_gem
    folder = File.expand_path("../examples/cmake_phone/gems/tally", __dir__)
    Fledge::PathGem.new(name: "tally", version: "1.0.0", folder:, app_path: "vendor/cache/tally", glob: "{,*,*/*}.gemspec", inside: true)
  end

  def cmake?
    system("cmake", "--version", out: File::NULL, err: File::NULL) || false
  end

  def test_fledge_build_ios_links_the_extensions_into_the_project
    runtimes = real_runtimes("ios")
    out = StringIO.new
    err = StringIO.new
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes, "XDG_CACHE_HOME" => File.join(@dir, "cache"))
    status = Fledge::CLI::Build.new(out:, err:, env:).call(["ios", "-o", File.join(@dir, "dist"), File.expand_path("../examples/native_phone", __dir__)])

    assert_equal 0, status, err.string
    project = File.join(@dir, "dist", "NativePhone-ios")
    assert_equal %w[Info.plist ios-arm64 ios-arm64-simulator], Dir.children(File.join(project, "FledgeExtensions.xcframework")).sort
    unit = File.read(File.join(project, "Host", "fledge_extensions.c"))
    assert_includes unit, 'fledge_ruby_add_extension("adder/adder", Init_fledge_0)'
    yml = File.read(File.join(project, "project.yml"))
    assert_includes yml, "- framework: FledgeExtensions.xcframework"
    assert_includes yml, 'OTHER_LDFLAGS: "$(inherited) -lc++"'
    marks = Dir.glob(File.join(project, "fledge", "lib", "ruby", "gems", "*", "**", "gem.build_complete"))
    assert_empty marks, "a path gem needs no mark, as on a desktop"
  end

  def real_runtimes(name)
    skip "Xcode builds the iOS slices on a Mac only" unless Fledge::Platform.local.name == "arm64-darwin" || name != "ios"
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
    phone = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(name)))
    skip "no #{File.basename(phone)} in #{dir}; run bundle exec rake runtime[#{name}]" unless File.file?(phone)
    dir
  end

  def path_gem(folder)
    Fledge::PathGem.new(name: "adder", version: "1.0.0", folder:, app_path: "vendor/cache/adder", glob: "{,*,*/*}.gemspec", inside: true)
  end

  def compile(runtimes_dir, phone, packages)
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes_dir)
    runtimes = Fledge::Runtimes.new(env:)
    tree = File.join(@dir, "tree")
    Fledge::Archive.unpack(runtimes.archive(phone), into: tree)
    log = StringIO.new
    Fledge::MobileExtensions.new(platform: phone, packages:, build_args: {}, host: Fledge::Platform.local, runtimes:,
      work: File.join(@dir, "work"), log:, env:).call(File.join(tree, Dir.children(tree).first))
  rescue Fledge::Error => e
    raise Fledge::Error, "#{e.message}\n#{log&.string}"
  end
end
