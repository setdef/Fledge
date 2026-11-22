# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Fledge::MobileProject::IOSLibraries: what an iOS app's frameworks of
# libraries for Ruby's ffi are named, what each one's Info.plist says,
# and the links at the paths where the gems look for them, from
# libraries described in memory. The frameworks themselves, made with
# Xcode's tools, are test/integration/mobile_extensions_build_test.rb's.
class IOSLibrariesTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # A framework is named for the gem and the library's path in it, as
  # Android's libfledgeffi.GEM.PATH.so is, with the characters a bundle
  # identifier cannot hold as hyphens, since the name ends one.
  def test_a_framework_is_named_for_its_gem_and_path_in_characters_a_bundle_identifier_takes
    names = [library("llhttp-ffi", "ext/aarch64-darwin/libllhttp-ext.bundle"), library("scrypt", "ext/scrypt/aarch64-darwin/libscrypt_ext.bundle")]
      .map { |each| Fledge::MobileProject::IOSLibraries.framework_name(each) }

    assert_equal %w[fledgeffi.llhttp-ffi.ext.aarch64-darwin.libllhttp-ext.bundle fledgeffi.scrypt.ext.scrypt.aarch64-darwin.libscrypt-ext.bundle],
      names
  end

  # The link is relative, so it reaches the framework from wherever the
  # bundle is: up out of fledge/ and each folder of the path, then into
  # Frameworks/. Both paths are expanded, since on Windows an expanded
  # path begins with the drive's letter.
  def test_a_link_leads_from_its_path_in_the_ruby_root_to_the_frameworks_binary
    target = Fledge::MobileProject::IOSLibraries.target("lib/ruby/gems/4.1.0+5/gems/thing-1.0.0/ext/libthing.bundle", "fledgeffi.thing")

    assert_equal "../../../../../../../../Frameworks/fledgeffi.thing.framework/fledgeffi.thing", target
    assert_equal File.expand_path("/App.app/Frameworks/fledgeffi.thing.framework/fledgeffi.thing"),
      File.expand_path(target, "/App.app/fledge/lib/ruby/gems/4.1.0+5/gems/thing-1.0.0/ext")
  end

  # Each slice's framework names its own platform, and the app's
  # identifier, version, and minimum iOS.
  def test_a_frameworks_info_plist_names_its_binary_platform_and_the_apps_identity
    info = Fledge::MobileProject::IOSLibraries.info("fledgeffi.thing", identifier: "com.example.Hello", version: "1.2.3",
      platform: "iPhoneSimulator")

    assert_equal({
      "CFBundleDevelopmentRegion" => "en",
      "CFBundleExecutable" => "fledgeffi.thing",
      "CFBundleIdentifier" => "com.example.Hello.fledgeffi.thing",
      "CFBundleInfoDictionaryVersion" => "6.0",
      "CFBundleName" => "fledgeffi.thing",
      "CFBundlePackageType" => "FMWK",
      "CFBundleShortVersionString" => "1.2.3",
      "CFBundleSupportedPlatforms" => ["iPhoneSimulator"],
      "CFBundleVersion" => "1.2.3",
      "MinimumOSVersion" => "15.0",
    }, info)
  end

  # The frameworks are the libraries of both slices, by name.
  def test_the_frameworks_hold_each_slices_library
    device = library("thing", "ext/libthing.bundle")
    simulator = library("thing", "ext/libthing.bundle")

    frameworks = libraries("ios-arm64" => [device], "ios-arm64-simulator" => [simulator]).frameworks

    assert_equal({ "fledgeffi.thing.ext.libthing.bundle" => { "ios-arm64" => device, "ios-arm64-simulator" => simulator } }, frameworks)
  end

  # Two libraries whose frameworks would have one name would overwrite
  # each other: refused, naming both.
  def test_two_libraries_with_one_frameworks_name_are_refused
    error = assert_raises(Fledge::Error) do
      libraries("ios-arm64" => [library("thing", "ext/a_b.so"), library("thing", "ext/a-b.so")]).frameworks
    end

    assert_equal "thing's ext/a_b.so and thing's ext/a-b.so would both be the framework fledgeffi.thing.ext.a-b.so in the iOS app",
      error.message
  end

  # One app holds one set of frameworks for both slices, as it registers
  # one set of extensions.
  def test_slices_that_built_different_libraries_are_refused
    error = assert_raises(Fledge::Error) do
      libraries("ios-arm64" => [library("thing", "ext/a.so")], "ios-arm64-simulator" => [library("thing", "ext/b.so")]).frameworks
    end

    assert_equal "the app's gems built different libraries for ffi for each iOS slice: ext/a.so and ext/b.so", error.message
  end

  # A link replaces the file the gem's package held at its path, as
  # llhttp-ffi 0.5.1's holds the library its author built on a Mac.
  def test_a_link_takes_the_place_of_the_packages_file_at_its_path
    root = File.join(@dir, "fledge")
    held = File.join(root, "app/gems/thing/ext/libthing.bundle")
    FileUtils.mkdir_p(File.dirname(held))
    File.write(held, "a Mac's library")
    thing = library("thing", "ext/libthing.bundle")

    libraries("ios-arm64" => [thing], "ios-arm64-simulator" => [thing]).link(root)

    assert_equal "../../../../../Frameworks/fledgeffi.thing.ext.libthing.bundle.framework/fledgeffi.thing.ext.libthing.bundle",
      File.readlink(held)
  end

  # Mach-O files are told by their first bytes; a Java class file, which
  # begins as a universal one does, is not one, and neither is a link.
  def test_mach_o_files_are_told_from_java_class_files_and_links
    files = {
      "thin" => [0xcffaedfe, 0x0c000001].pack("NN"),
      "universal" => [0xcafebabe, 2].pack("NN"),
      "class" => [0xcafebabe, 0x41].pack("NN"),
      "text" => "puts 1\n",
    }
    files.each { |name, bytes| File.binwrite(File.join(@dir, name), bytes) }
    File.symlink("thin", File.join(@dir, "link"))

    found = %w[thin universal class text link].select { |name| Fledge::MobileProject::IOS.mach_o?(File.join(@dir, name)) }

    assert_equal %w[thin universal], found
  end

  private def library(gem, file)
    Fledge::MobileExtensions::FfiLibrary.new(gem:, file:, path: File.join(@dir, File.basename(file)), links: ["app/gems/#{gem}/#{file}"])
  end

  private def libraries(slices)
    targets = slices.to_h do |slice, ffi_libraries|
      target = Fledge::MobileExtensions::Target.new(name: slice, root: @dir, arch_dir: @dir, libdir: @dir, environment: {}, abi: nil)
      [slice, Fledge::MobileExtensions::TargetBuild.new(target:, archives: [], flags: [], cxx: false, libraries: [], ffi_libraries:)]
    end
    built = Fledge::MobileExtensions::Built.new(registrations: [], targets:, ndk: nil, stubs: [], left: [], apart: {})
    Fledge::MobileProject::IOSLibraries.new(built, identifier: "com.example.Hello", version: "1.0.0")
  end
end
