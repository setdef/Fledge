# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "digest"
require "yaml"

# The phones fledge build writes projects for (ADR 012), where each is
# built, and the pins of the tools their projects name, which must be the
# ones Fledge's runtimes are built and checked with (runtime/sources.yml).
class MobilePlatformTest < Minitest::Test
  SOURCES = YAML.safe_load_file(File.expand_path("../runtime/sources.yml", __dir__)).fetch("mobile")
  ANDROID = File.join(Fledge::MobileProject::TEMPLATES, "android")

  def test_ios_and_android_are_the_phones
    assert_equal %w[ios android], Fledge::MobilePlatform.names
    assert_equal "ios", Fledge::MobilePlatform.find("ios").to_s
    assert_nil Fledge::MobilePlatform.find("x86_64-linux")
    assert_nil Fledge::MobilePlatform.find("")
  end

  # A phone's Bundler resolves its lockfile with force_ruby_platform, so
  # the lockfile must lock ruby, and a desktop's never does.
  def test_a_phones_gems_are_ruby_ones
    android = Fledge::MobilePlatform.find("android")
    assert_equal [["ruby"], true, false], [android.lockfile_names, android.force_ruby_platform?, android.windows?]
    refute_predicate Fledge::Platform.find("arm64-darwin"), :force_ruby_platform?
  end

  def test_each_phone_is_built_where_its_tools_run
    {
      "ios" => %w[arm64-darwin],
      "android" => %w[arm64-darwin x86_64-linux x64-mingw-ucrt],
    }.each do |phone, hosts|
      Fledge::Platform.names.each do |host|
        check = -> { Fledge::MobilePlatform.find(phone).check_host(Fledge::Platform.find(host)) }
        hosts.include?(host) ? check.call : assert_raises(Fledge::Error, "#{phone} on #{host}", &check)
      end
    end
  end

  def test_the_android_project_pins_the_gradle_and_plugin_the_runtime_is_built_with
    gradle = SOURCES.fetch("gradle")
    wrapper = File.read(File.join(ANDROID, "gradle/wrapper/gradle-wrapper.properties"))
    assert_includes wrapper, "distributionUrl=#{gradle.fetch('url').sub(':', '\\:')}\n"
    assert_includes wrapper, "distributionSha256Sum=#{gradle.fetch('sha256')}\n"
    assert_equal gradle.fetch("wrapper_sha256"), Digest::SHA256.file(File.join(ANDROID, "gradle/wrapper/gradle-wrapper.jar")).hexdigest
    assert_equal SOURCES.fetch("agp"), Fledge::MobileProject::Android::AGP
    assert File.executable?(File.join(ANDROID, "gradlew")), "Gradle's wrapper is executable"
  end

  # The privacy manifest names a category for each API Apple requires a
  # reason for that Fledge's Ruby imports (the Mobile apps job checks
  # the imports of each built app against PRIVACY_APIS).
  def test_the_privacy_manifest_has_a_reason_for_each_category_ruby_needs
    manifest = File.read(File.join(Fledge::MobileProject::TEMPLATES, "ios/Host/PrivacyInfo.xcprivacy"))
    {
      "NSPrivacyAccessedAPICategoryFileTimestamp" => "C617.1",
      "NSPrivacyAccessedAPICategorySystemBootTime" => "35F9.1",
    }.each do |category, reason|
      assert_match(%r{<string>#{category}</string>\s*<key>NSPrivacyAccessedAPITypeReasons</key>\s*<array>\s*<string>#{reason}</string>},
        manifest)
    end
  end
end
