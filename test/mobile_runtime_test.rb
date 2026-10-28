# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# The parts of the mobile runtimes (ADR 011) that need no Xcode or NDK:
# their names and targets, their pins, their release assets, the edits
# they make to Ruby's source, and how Ruby's bundled gems with C
# extensions stay gems. CI's mobile runtime jobs build the real ones, and
# its mobile parity jobs run them in the iOS Simulator and an Android
# emulator.
class MobileRuntimeTest < Minitest::Test
  def mobile(name)
    RuntimeBuilder.platform(name)
  end

  def test_ios_and_android_are_runtimes_of_two_targets_each
    assert_equal %w[ios android], RuntimeBuilder::Mobile::PLATFORMS.keys
    assert_equal %w[arm64-ios arm64-ios-simulator], mobile("ios").targets.map(&:name)
    assert_equal %w[aarch64-linux-android x86_64-linux-android], mobile("android").targets.map(&:name)
    assert_equal "ios", mobile("ios").to_s
    refute_predicate mobile("android"), :windows?
  end

  # iOS's CRuby reports arm64-darwin, as macOS's does, so a target named
  # after RUBY_PLATFORM would let Bundler pick a macOS gem that can never
  # load on a phone. RubyGems knows no iOS, and reads "ios" as an unknown
  # system, which no published gem names; Android's names are Ruby's own
  # RUBY_PLATFORM there, which RubyGems reads as Linux with Android's C
  # library, which no glibc or musl gem fits.
  def test_no_desktop_gem_fits_a_mobile_target
    desktop = %w[
      arm64-darwin
      arm64-darwin-23
      universal-darwin
      aarch64-linux
      aarch64-linux-gnu
      aarch64-linux-musl
      x86_64-linux
      x86_64-linux-musl
    ]
    %w[arm64-ios arm64-ios-simulator aarch64-linux-android x86_64-linux-android].each do |target|
      desktop.each { |name| refute Gem::Platform.new(name) === Gem::Platform.new(target), "#{name} fits #{target}" }
    end
    assert_equal %w[arm64 darwin], mobile("ios").targets.map(&:ruby_platform).uniq.first.split("-")
    assert_equal %w[aarch64 linux android], Gem::Platform.new("aarch64-linux-android").to_a
  end

  def test_each_target_names_the_toolchain_it_builds_with
    device, simulator = mobile("ios").targets
    assert_equal ["iphoneos", "arm64-apple-ios15.0", "ios64-xcrun", "ios-arm64"], [device.sdk, device.triple, device.openssl, device.slice]
    assert_equal ["iphonesimulator", "arm64-apple-ios15.0-simulator", "iossimulator-arm64-xcrun", "ios-arm64-simulator"],
      [simulator.sdk, simulator.triple, simulator.openssl, simulator.slice]
    arm, intel = mobile("android").targets
    assert_equal %w[arm64-v8a aarch64-linux-android android-arm64], [arm.abi, arm.triple, arm.openssl]
    assert_equal %w[x86_64 x86_64-linux-android android-x86_64], [intel.abi, intel.triple, intel.openssl]
  end

  # Each mobile runtime builds on the system that has its tools: iOS on a
  # Mac, with Xcode, and Android on Linux, or a Mac, with the NDK.
  def test_each_mobile_runtime_builds_where_its_tools_run
    assert_equal %w[arm64-darwin], mobile("ios").hosts
    assert_equal %w[x86_64-linux arm64-darwin], mobile("android").hosts
    error = assert_raises(RuntimeError) { RuntimeBuilder.new(platform: mobile("ios"), host: Fledge::Platform.find("x86_64-linux")).call }
    assert_equal "ios runtimes build on arm64-darwin only; this is x86_64-linux", error.message
  end

  def test_every_mobile_input_is_pinned_by_sha256
    pins = RuntimeBuilder.new(platform: mobile("ios")).sources.fetch("mobile")

    %w[ruby openssl libyaml libffi ca-certificates gradle xcodegen].each do |name|
      assert_match(%r{\Ahttps://}, pins.fetch(name).fetch("url"), name)
      assert_match(/\A\h{64}\z/, pins.fetch(name).fetch("sha256"), name)
    end
    assert_equal %w[arm64-darwin x86_64-linux], pins.fetch("ndk").fetch("hosts").keys.sort
    assert_equal "4.0.9", pins.fetch("ruby").fetch("version")
    assert_equal RuntimeBuilder.new.sources.fetch("ruby").fetch("version"), pins.fetch("ruby").fetch("version")
  end

  # A mobile runtime has no build-only companion, since its headers are
  # in it, and no LGPL library, so its release carries the runtime, its
  # SBOM, and its NOTICES.
  def test_a_release_publishes_each_mobile_runtime_with_its_sbom_and_notices
    assets = RuntimeBuilder.release_assets(version: "1.2.3")

    %w[ios android].each do |name|
      assert_includes assets, "fledge-runtime-1.2.3-#{name}.tar.gz"
      assert_includes assets, "fledge-runtime-1.2.3-#{name}.spdx.json"
      assert_includes assets, "fledge-runtime-1.2.3-#{name}-NOTICES.txt"
      refute_includes assets, "fledge-runtime-1.2.3-#{name}-dev.tar.gz"
      refute_includes assets, "fledge-runtime-1.2.3-#{name}-lgpl-sources.tar.gz"
    end
    ios = { runtime: "fledge-runtime-1.2.3-ios.tar.gz", sbom: "fledge-runtime-1.2.3-ios.spdx.json", notices: "fledge-runtime-1.2.3-ios-NOTICES.txt" }
    assert_equal ios, RuntimeBuilder.new(platform: mobile("ios")).assets(version: "1.2.3")
  end

  def test_platform_finds_desktop_and_mobile_runtimes_by_name
    assert_equal Fledge::Platform.find("x86_64-linux"), RuntimeBuilder.platform("x86_64-linux")
    assert_equal "android", RuntimeBuilder.platform("android").name
    assert_raises(Fledge::UsageError) { RuntimeBuilder.platform("arm64-ios") }
  end
end
