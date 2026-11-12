# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "stringio"

# Native gems on phones (ADR 022), compiled for real: a gem's extension
# for every target of a phone, with the real mobile runtimes and tools
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
      [name, Open3.capture2(readelf, "-h", library).first[/Machine:\s+(.+)$/, 1]]
    end
    assert_equal({ "aarch64-linux-android" => "AArch64", "x86_64-linux-android" => "Advanced Micro Devices X86-64" }, machines)
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
    yml = File.read(File.join(project, "project.yml"))
    assert_includes yml, "- framework: FledgeExtensions.xcframework"
    assert_includes yml, 'OTHER_LDFLAGS: "$(inherited) -lc++"'
    marks = Dir.glob(File.join(project, "fledge", "lib", "ruby", "gems", "*", "**", "gem.build_complete"))
    assert_empty marks, "a path gem needs no mark, as on a desktop"
  end

  def tally_gem
    folder = File.expand_path("../../examples/cmake_phone/gems/tally", __dir__)
    Fledge::PathGem.new(name: "tally", version: "1.0.0", folder:, app_path: "vendor/cache/tally", glob: "{,*,*/*}.gemspec", inside: true)
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
