# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"

# Native gems on phones (ADR 022): which extensions Fledge compiles, how
# the registration unit and the link flags are written, and where an
# Android NDK is found. test/integration/mobile_extensions_build_test.rb
# compiles a real gem for every target of a phone, with the real mobile
# runtimes and tools where this computer has them.
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

  # RubyGems runs Rake for a Rakefile or an mkrf_conf script
  # (Gem::Ext::Builder#builder_for), and Fledge runs that builder aimed
  # at the phone (Fledge::MobileExtensions::RubyGemsBuild).
  def test_an_extension_rake_builds_is_one_fledge_compiles
    %w[ext/native/Rakefile ext/native/rakefile.rb ext/native/mkrf_conf.rb].each do |builder|
      gem, package = native_gem(extensions: [builder])

      assert_empty Fledge::MobileExtensions.problems(gem, package, ios, Fledge::Platform.find("arm64-darwin")), builder
      assert_empty Fledge::MobileExtensions.problems(gem, package, android, Fledge::Platform.find("x86_64-linux")), builder
    end
  end

  # As RubyGems' own choice, an extconf or a configure in the path comes
  # before a Rakefile.
  def test_rake_builds_what_rubygems_gives_rake
    assert Fledge::MobileExtensions.rake?("ext/digest/Rakefile")
    assert Fledge::MobileExtensions.rake?("ext/mkrf_conf.rb")
    refute Fledge::MobileExtensions.rake?("ext/rakefile_extconf.rb")
    refute Fledge::MobileExtensions.rake?("ext/configure/Rakefile")
    refute Fledge::MobileExtensions.rake?("ext/native/CMakeLists.txt")
  end

  def test_any_other_way_to_build_an_extension_is_refused_by_gem_and_by_what_to_do
    %w[CMakeLists.txt configure Cargo.toml].each do |builder|
      gem, package = native_gem(extensions: [builder])

      problems = Fledge::MobileExtensions.problems(gem, package, ios, Fledge::Platform.find("arm64-darwin"))

      assert_equal 1, problems.size, builder
      assert_includes problems.first, "native 1.0.0 has an extension built by #{builder}"
      assert_includes problems.first, "an extconf.rb or a Rakefile"
      assert_includes problems.first, 'gem "native", platforms: [...]'
    end
  end

  # An extconf.rb that writes rb-sys's Makefile is compiled for a phone as
  # any other: Cargo builds a static library (MobileExtensions::Rust).
  def test_a_rust_extension_through_rb_sys_is_one_fledge_compiles
    gem, package = native_gem(name: "oxide", dependencies: { "rb_sys" => ">= 0" })

    assert_empty Fledge::MobileExtensions.problems(gem, package, ios, Fledge::Platform.find("arm64-darwin"))
    assert_empty Fledge::MobileExtensions.problems(gem, package, android, Fledge::Platform.find("x86_64-linux"))
  end

  # Cargo's target for each target of a phone, which the runtime's
  # targets name by an XCFramework slice or an Android Ruby architecture.
  def test_each_phone_target_has_rusts_own_target
    assert_equal %w[aarch64-apple-ios aarch64-apple-ios-sim aarch64-linux-android x86_64-linux-android],
      %w[ios-arm64 ios-arm64-simulator aarch64-linux-android x86_64-linux-android].map { |name| Fledge::MobileExtensions::Rust.triple(name) }
    assert_raises(Fledge::Error) { Fledge::MobileExtensions::Rust.triple("arm64-darwin") }
  end

  # An iOS slice aims Cargo and rustc at Rust's target for it, with the
  # deployment target of the runtime's triple, bindgen alone at the
  # slice's SDK, and rb-sys at iOS, the system Rust names.
  def test_rust_for_an_ios_slice_takes_its_target_deployment_target_and_sdk
    environment = Fledge::MobileExtensions::Rust.ios("ios-arm64-simulator", triple: "arm64-apple-ios15.0-simulator", sysroot: "/Xcode/Sim.sdk")

    assert_equal({
      "CARGO_BUILD_TARGET" => "aarch64-apple-ios-sim",
      "IPHONEOS_DEPLOYMENT_TARGET" => "15.0",
      "BINDGEN_EXTRA_CLANG_ARGS_aarch64_apple_ios_sim" => "-isysroot /Xcode/Sim.sdk",
      "FLEDGE_RUST_TARGET_OS" => "ios",
    }, environment)
  end

  # An Android ABI gives the cc crate the NDK's compilers for the target
  # alone, and bindgen the NDK's own libclang, with its own headers, the
  # NDK's sysroot, and the target with the API level the compiler's name
  # holds, as the NDK's headers ask, so a build script compiled for this
  # computer keeps this computer's compilers.
  def test_rust_for_an_android_abi_takes_the_ndks_compilers_for_that_target_alone
    bin = "/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
    resource = "/ndk/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/21"
    environment = Fledge::MobileExtensions::Rust.android("x86_64-linux-android", bin:, cc: "#{bin}/x86_64-linux-android26-clang", resource:)

    assert_equal({
      "CARGO_BUILD_TARGET" => "x86_64-linux-android",
      "CC_x86_64_linux_android" => "#{bin}/x86_64-linux-android26-clang",
      "CXX_x86_64_linux_android" => "#{bin}/x86_64-linux-android26-clang++",
      "AR_x86_64_linux_android" => "#{bin}/llvm-ar",
      "LIBCLANG_PATH" => "/ndk/toolchains/llvm/prebuilt/linux-x86_64/lib",
      "BINDGEN_EXTRA_CLANG_ARGS_x86_64_linux_android" =>
        "--target=x86_64-linux-android26 --sysroot=/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot -resource-dir #{resource}",
    }, environment)
  end

  # The native libraries rustc names for a static library link with it,
  # but on iOS those that are libSystem are left out: every iOS program
  # links libSystem already, and xcodebuild warns of a duplicate library
  # otherwise, which App Store archiving must not.
  def test_rusts_native_libraries_link_without_libsystem_on_ios
    printed = "-liconv -lSystem -lc -lm -lpthread"

    assert_equal ["-liconv"], Fledge::MobileExtensions::Rust.link_flags(printed, dir: @dir, apple: true)
    assert_equal %w[-ldl -llog -lunwind -lm -lc], Fledge::MobileExtensions::Rust.link_flags("-ldl -llog -lunwind -lm -lc", dir: @dir, apple: false)
  end

  # Without Rust, or without its standard library for the target, the
  # build says which target to add, naming the gem.
  def test_a_missing_rust_says_which_target_to_add
    error = assert_raises(Fledge::Error) do
      Fledge::MobileExtensions::Rust.check("aarch64-apple-ios", gem: "oxide 1.0.0", env: { "PATH" => @dir })
    end

    assert_includes error.message, "oxide 1.0.0 is a Rust extension"
    assert_includes error.message, "rustup target add aarch64-apple-ios"
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

  # The ffi gem's extconf.rb appends to the Makefile mkmf wrote a makefile
  # that adds the libffi it builds to LOCAL_LIBS, which the extension's
  # shared library links on a desktop, so a phone's link must take it
  # too. Make reads the value from the whole Makefile, quotes and all,
  # and builds nothing.
  def test_what_a_makefile_adds_to_local_libs_after_mkmf_is_linked
    File.write(File.join(@dir, "Makefile"), <<~MAKE)
      LOCAL_LIBS = ./libown.a
      all:
      \tfalse
      include extra.mk
    MAKE
    File.write(File.join(@dir, "extra.mk"), "BUILD_DIR = $(shell pwd)\nLOCAL_LIBS += \"$(BUILD_DIR)/libffi-x\"/.libs/libffi_convenience.a\n")

    libs = Fledge::MobileExtensions::Linking.local_libs({}, @dir)

    here = File.realpath(@dir)
    assert_equal %(./libown.a "#{here}/libffi-x"/.libs/libffi_convenience.a), libs
    assert_equal [File.join(@dir, "libown.a"), "#{here}/libffi-x/.libs/libffi_convenience.a"],
      Fledge::MobileExtensions::Linking.link_flags(libs, dir: @dir)
  end

  # On Windows, MSYS2's make prints what $(shell pwd) gave, a folder's
  # POSIX path, which Ruby and the linker read as a path on the current
  # drive. Each drive path where a word, a quoted word, or a -I or -L
  # flag begins is read as Windows names it, and nothing else changes.
  def test_an_msys2_drive_path_make_prints_is_read_as_windows_names_it
    text = %(./libown.a "/d/a/_temp/libffi-x"/.libs/libffi_convenience.a -L/c/lib -I/c/include '/e/q' /usr/lib/x.a lib/d/a.a)

    assert_equal %(./libown.a "D:/a/_temp/libffi-x"/.libs/libffi_convenience.a -LC:/lib -IC:/include 'E:/q' /usr/lib/x.a lib/d/a.a),
      Fledge::MobileExtensions::Linking.windows_paths(text)
  end

  def test_a_makefile_make_cannot_read_is_an_error_naming_its_folder
    File.write(File.join(@dir, "Makefile"), "include missing.mk\n")

    error = assert_raises(Fledge::Error) { Fledge::MobileExtensions::Linking.local_libs({}, @dir) }
    assert_includes error.message, "make could not read the Makefile in #{@dir}"
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

  # A git gem's checkout is copied whole into a folder of the target's
  # own, which the copy makes along with the folders above it, and its
  # extension paths are relative to the gemspec's folder in it.
  def test_a_git_gems_source_is_copied_into_a_new_folder_of_the_targets
    checkout = File.join(@dir, "checkout")
    FileUtils.mkdir_p(File.join(checkout, "gems", "oxide", "ext", "oxide"))
    File.write(File.join(checkout, "gems", "oxide", "ext", "oxide", "extconf.rb"), "# extconf\n")
    File.write(File.join(checkout, "gems", "oxide", "oxide.gemspec"), <<~RUBY)
      Gem::Specification.new { |spec| spec.name = "oxide"; spec.version = "1.0.0"; spec.summary = "oxide"; spec.authors = ["a"]; spec.extensions = ["ext/oxide/extconf.rb"] }
    RUBY
    gem = Fledge::GitGem.new(name: "oxide", version: "1.0.0", uri: "https://example.com/oxide.git", revision: "a" * 40,
      glob: "gems/*/*.gemspec", ref: nil, submodules: false)
    compiler = Fledge::MobileExtensions.new(platform: ios, packages: {}, build_args: {}, host: Fledge::Platform.find("arm64-darwin"),
      runtimes: Fledge::Runtimes.new(env: {}), work: File.join(@dir, "work"), log: StringIO.new)

    root = compiler.__send__(:source_root, Fledge::GitPackage.new(gem, checkout), File.join(@dir, "work", "ios-arm64", "oxide-1.0.0"))

    assert_equal File.join(@dir, "work", "ios-arm64", "oxide-1.0.0", "gems", "oxide"), root
    assert_equal "# extconf\n", File.read(File.join(root, "ext", "oxide", "extconf.rb"))
  end

  def test_a_gem_without_extensions_asks_for_no_compiler
    gem, package = native_gem(extensions: [], files: { "lib/pure.rb" => "" })

    assert_empty Fledge::MobileExtensions.problems(gem, package, ios, Fledge::Platform.find("arm64-darwin"))
  end
end
