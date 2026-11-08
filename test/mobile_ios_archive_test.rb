# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "zlib"
require_relative "test_helper"
require_relative "../tasks/mobile_parity"

# The parts of the iOS archive check (ADR 012, section 10) that need no
# xcodebuild: what App Store Connect requires of an app's Info.plist, of
# its icon, and of the files in its bundle, read from a real property
# list that plutil made. CI's Mobile apps (iOS) job archives each app.
class MobileIOSArchiveTest < Minitest::Test
  APP = { "name" => "Mobile App", "identifier" => "com.example.MobileApp" }.freeze

  # What Xcode writes into the Info.plist of an app built from the
  # template for a device (measured on an archive of examples/mobile_app).
  def info
    {
      "CFBundleIdentifier" => APP["identifier"],
      "CFBundleExecutable" => APP["name"],
      "CFBundleName" => APP["name"],
      "CFBundlePackageType" => "APPL",
      "CFBundleShortVersionString" => "1.2.3",
      "CFBundleVersion" => "1.2.3",
      "CFBundleSupportedPlatforms" => ["iPhoneOS"],
      "DTPlatformName" => "iphoneos",
      "DTSDKName" => "iphoneos27.2",
      "DTXcode" => "2720",
      "MinimumOSVersion" => "15.0",
      "UIDeviceFamily" => [1, 2],
      "UIRequiredDeviceCapabilities" => ["arm64"],
      "UILaunchScreen" => {},
      "CFBundleIcons" => { "CFBundlePrimaryIcon" => { "CFBundleIconName" => "AppIcon", "CFBundleIconFiles" => ["AppIcon60x60"] } },
    }
  end

  def problems(info, icon: true)
    MobileParity::IOSArchive.info_problems(info, identifier: APP["identifier"], executable: APP["name"], icon:)
  end

  # Reads +hash+ back as plutil converts the property list the way the
  # check reads Info.plist: through a file, not through Ruby's own types.
  def through_plutil(hash)
    skip "plutil is Apple's" unless RUBY_PLATFORM.include?("darwin")
    Dir.mktmpdir do |dir|
      plist = File.join(dir, "Info.plist")
      File.write(plist, JSON.generate(hash))
      system("plutil", "-convert", "xml1", plist, exception: true)
      return MobileParity::IOSArchive.read_plist(plist)
    end
  end

  def test_an_info_plist_xcode_wrote_passes
    assert_empty problems(through_plutil(info))
  end

  def test_each_key_app_store_connect_requires_is_named_when_it_is_missing
    %w[
      CFBundleIdentifier
      CFBundleExecutable
      CFBundleName
      CFBundlePackageType
      CFBundleShortVersionString
      CFBundleVersion
      MinimumOSVersion
      UIDeviceFamily
      UIRequiredDeviceCapabilities
      DTXcode
].each do |key|
      found = problems(info.except(key))

      assert_equal 1, found.size, key
      assert_includes found.first, key
    end
  end

  def test_a_launch_screen_is_a_dictionary_or_a_storyboard
    assert_empty problems(info.except("UILaunchScreen").merge("UILaunchStoryboardName" => "Main"))
    assert_includes problems(info.except("UILaunchScreen")).first, "UILaunchScreen"
  end

  def test_versions_are_one_to_three_integers
    ["1.2.3.4", "1.2.pre", "", "v1"].each do |version|
      assert_includes problems(info.merge("CFBundleVersion" => version)).first, "CFBundleVersion", version
      assert_includes problems(info.merge("CFBundleShortVersionString" => version)).first, "CFBundleShortVersionString", version
    end
    assert_empty problems(info.merge("CFBundleVersion" => "7", "CFBundleShortVersionString" => "2.1"))
  end

  def test_the_app_is_for_iphone_and_ipad_on_arm64_built_for_a_device
    assert_includes problems(info.merge("UIDeviceFamily" => [1])).first, "UIDeviceFamily"
    assert_includes problems(info.merge("UIRequiredDeviceCapabilities" => ["metal"])).first, "arm64"
    assert_includes problems(info.merge("DTPlatformName" => "iphonesimulator")).first, "iphoneos"
    assert_includes problems(info.merge("CFBundleSupportedPlatforms" => ["iPhoneSimulator"])).first, "iPhoneOS"
  end

  def test_the_identifier_and_the_executable_are_the_apps
    assert_includes problems(info.merge("CFBundleIdentifier" => "com.example.Other")).first, "com.example.MobileApp"
    assert_includes problems(info.merge("CFBundleExecutable" => "Other")).first, "Mobile App"
  end

  # An app with an icon names the asset catalog's app icon, whose 1024
  # pixel image is the store's; an app with none has none to name.
  def test_the_icon_is_named_when_the_app_has_one
    assert_includes problems(info.merge("CFBundleIcons" => {})).first, "CFBundleIconName"
    assert_empty problems(info.except("CFBundleIcons"), icon: false)
  end

  def test_the_encryption_declaration_is_reported_not_required
    assert_equal "not declared", MobileParity::IOSArchive.encryption(info)
    assert_equal "declared false", MobileParity::IOSArchive.encryption(info.merge("ITSAppUsesNonExemptEncryption" => false))
    assert_equal "declared true", MobileParity::IOSArchive.encryption(info.merge("ITSAppUsesNonExemptEncryption" => true))
  end

  def png(color_type, extra: "")
    header = [1024, 1024, 8, color_type, 0, 0, 0].pack("NNCCCCC")
    chunk = -> (type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
    "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", header) + extra.b + chunk.call("IEND", "")
  end

  # App Store Connect refuses a large app icon with an alpha channel, even
  # an opaque one, so the check reads the PNG's color type and chunks.
  def test_a_png_has_alpha_when_its_color_type_or_a_chunk_says_so
    Dir.mktmpdir do |dir|
      cases = { 2 => false, 0 => false, 6 => true, 4 => true }
      cases.each do |color_type, alpha|
        file = File.join(dir, "#{color_type}.png")
        File.binwrite(file, png(color_type))

        assert_equal alpha, MobileParity::IOSArchive.alpha?(file), "color type #{color_type}"
      end
      transparent = File.join(dir, "trns.png")
      File.binwrite(transparent, png(2, extra: "#{[3].pack('N')}tRNS\0\0\0#{[Zlib.crc32("tRNS\0\0\0")].pack('N')}"))

      assert MobileParity::IOSArchive.alpha?(transparent)
    end
  end

  def test_the_examples_app_icon_has_no_alpha
    icon = File.join(MobileParity::ROOT, "examples", "mobile_app", "icons", "app-1024.png")

    refute MobileParity::IOSArchive.alpha?(icon)
  end

  # A Mach-O file in the bundle other than the executable is a library
  # or a program App Store Connect would want signed and in a framework.
  def test_a_mach_o_file_is_found_by_its_magic_number
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "fledge", "lib"))
      File.binwrite(File.join(dir, "Exe"), [0xfeedfacf].pack("V"))
      File.binwrite(File.join(dir, "fledge", "lib", "ext.bundle"), "#{[0xfeedfacf].pack('V')}x")
      File.binwrite(File.join(dir, "fledge", "lib", "fat.so"), "#{[0xcafebabe].pack('N')}x")
      File.binwrite(File.join(dir, "fledge", "lib", "a.rb"), "puts 1\n")
      File.binwrite(File.join(dir, "fledge", "lib", "tiny"), "x")

      assert_equal %w[fledge/lib/ext.bundle fledge/lib/fat.so], MobileParity::IOSArchive.mach_o_files(dir, except: "Exe")
    end
  end
end
