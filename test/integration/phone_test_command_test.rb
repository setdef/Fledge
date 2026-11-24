# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../support/android"
require_relative "../support/ios"

# fledge test, as a developer runs it (doc/contributors/design/phone-projects.md,
# "Tests in the app"): examples/basket's test program, whose tests of
# its screen make UIKit's or Android's own widgets, and
# test/fixtures/phone_tests' two, one that passes and one that fails,
# each built into its app and run on a Simulator of the test's own, or
# on the Android emulator ANDROID_SERIAL names, with fledge test's
# status and output checked. Without the runtime, the tools, or a
# Simulator or device they skip, and fail instead where
# FLEDGE_REQUIRE_IOS or FLEDGE_REQUIRE_ANDROID is set.
class PhoneTestCommandTest < Minitest::Test
  include AndroidRequired
  include IOSRequired

  ROOT = File.expand_path("../..", __dir__)

  BASKET = File.join(ROOT, "examples", "basket", "test", "phone.rb")
  PASSES = File.join(ROOT, "test", "fixtures", "phone_tests", "test", "passes.rb")
  FAILS = File.join(ROOT, "test", "fixtures", "phone_tests", "test", "fails.rb")

  def setup
    @dir = Fledge::LongPath.of(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_ios_runs_the_tests_in_the_app_and_exits_with_their_status
    ios_missing("Xcode builds an iOS app on a Mac only") unless Fledge::Platform.local.name == "arm64-darwin"
    runtimes("ios")
    simulator do |udid|
      assert_passes fledge_test("ios", "-d", udid, BASKET), runs: 7
      assert_passes fledge_test("ios", "-d", udid, PASSES), runs: 1, warns: true
      assert_fails fledge_test("ios", "-d", udid, FAILS)
    end
  end

  def test_android_runs_the_tests_in_the_app_and_exits_with_their_status
    android_missing("no Android device or emulator: set ANDROID_SERIAL, as bin/android-emulator does") unless ENV["ANDROID_SERIAL"]
    runtimes("android")
    assert_passes fledge_test("android", BASKET), runs: 8
    assert_passes fledge_test("android", PASSES), runs: 1, warns: true
    assert_fails fledge_test("android", FAILS)
  ensure
    %w[Basket PhoneTests].each do |name|
      system("adb", "uninstall", "com.setdef.fledge.#{name}", out: File::NULL, err: File::NULL) if ENV["ANDROID_SERIAL"]
    end
  end

  # Runs fledge test with +arguments+ and returns its standard output,
  # its standard error, and its status.
  private def fledge_test(*arguments)
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "fledge"), "test", arguments.first,
      "-o", File.join(@dir, "dist"), *arguments.drop(1), chdir: ROOT)
    [out, err, status.exitstatus]
  end

  # That fledge test exited 0 and printed Minitest's summary of +runs+
  # tests passing, and the warning PASSES prints when +warns+.
  private def assert_passes(result, runs:, warns: false)
    out, err, status = result
    assert_equal 0, status, "fledge test passes:\n#{out}\n#{err}"
    assert_match(/^#{runs} runs, \d+ assertions, 0 failures, 0 errors, 0 skips$/, out)
    assert_includes err, "PhoneTests warns on standard error\n" if warns
  end

  # That fledge test exited 1, as ruby FAILS does, and printed the
  # failure.
  private def assert_fails(result)
    out, err, status = result
    assert_equal 1, status, "fledge test fails:\n#{out}\n#{err}"
    assert_includes out, "PhoneTests fails on purpose"
    assert_match(/^2 runs, 2 assertions, 1 failures, 0 errors, 0 skips$/, out)
  end

  # Makes and boots a Simulator of the newest iOS runtime, an iPhone,
  # yields its UDID, and deletes it.
  private def simulator
    runtimes = JSON.parse(capture("xcrun", "simctl", "list", "runtimes", "-j")).fetch("runtimes")
    runtime = runtimes.select { |candidate| candidate["platform"] == "iOS" && candidate["isAvailable"] }
      .max_by { |candidate| Gem::Version.new(candidate.fetch("version")) } or ios_missing("this Mac has no iOS Simulator runtime")
    type = runtime.fetch("supportedDeviceTypes").reverse.find { |candidate| candidate["productFamily"] == "iPhone" } or flunk "no iPhone"
    udid = capture("xcrun", "simctl", "create", "fledge-test-command", type.fetch("identifier"), runtime.fetch("identifier")).strip
    begin
      capture("xcrun", "simctl", "bootstatus", udid, "-b")
      yield udid
    ensure
      system("xcrun", "simctl", "shutdown", udid, out: File::NULL, err: File::NULL)
      system("xcrun", "simctl", "delete", udid, out: File::NULL, err: File::NULL)
    end
  end

  private def capture(*command)
    out, status = Open3.capture2e(*command)
    assert_predicate status, :success?, "#{command.join(' ')}:\n#{out}"
    out
  end

  # The folder of the runtimes, which holds +phone+'s.
  private def runtimes(phone)
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    file = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(phone)))
    message = "no #{File.basename(file)} in #{dir}; run bundle exec rake runtime[#{phone}]"
    (phone == "ios") ? ios_missing(message) : android_missing(message) unless File.file?(file)
    dir
  end
end
