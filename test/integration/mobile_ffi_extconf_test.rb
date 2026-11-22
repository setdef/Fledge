# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "stringio"
require_relative "../support/android"
require_relative "../support/ios"
require_relative "../../tasks/mobile_parity"

# A gem whose extconf.rb builds a library for Ruby's ffi with no Init
# function, as sassc's builds libsass, on a phone
# (doc/contributors/design/phone-projects.md, "Gems with extensions"):
# test/fixtures/ffi_extconf, whose gem's Ruby opens the library by the
# path where RubyGems copies it into the gem's lib/, and calls it. fledge
# build writes the app's Xcode or Gradle project, Xcode or Gradle builds
# it, and it runs on the iOS Simulator or the attached Android device as
# tasks/mobile_parity.rb runs the examples. Without the runtime, the
# tools, or a Simulator or device they skip, and fail instead where
# FLEDGE_REQUIRE_IOS or FLEDGE_REQUIRE_ANDROID is set.
class MobileFfiExtconfTest < Minitest::Test
  include AndroidRequired
  include IOSRequired

  FIXTURE = File.expand_path("../fixtures/ffi_extconf", __dir__)

  def setup
    @dir = Fledge::LongPath.of(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_an_ios_app_opens_a_library_for_ffi_an_extconf_rb_built
    ios_missing("Xcode builds an iOS app on a Mac only") unless Fledge::Platform.local.name == "arm64-darwin"
    runtimes = runtimes("ios")
    app = app("FfiExtconfIOS")
    project = MobileParity.projects("ios", runtimes:, out: File.join(@dir, "dist"), apps: [app]).fetch(app)
    FileUtils.mkdir_p(File.join(@dir, "ios"))
    ios = MobileParity::IOS.new(runtimes:, work: File.join(@dir, "ios"), out: StringIO.new)
    bundle = ios.build_app(app, project)
    printed = nil
    ios.on_simulator("iPhone", { app => bundle }) { |_, logged, _| printed = logged }

    refute_nil printed, "the Simulator ran #{app.name}"
    assert_said "bundle", printed
  end

  def test_an_android_app_opens_a_library_for_ffi_an_extconf_rb_built
    android_missing("no Android device or emulator: set ANDROID_SERIAL, as bin/android-emulator does") unless ENV["ANDROID_SERIAL"]
    app = app("FfiExtconfAndroid")
    project = MobileParity.projects("android", runtimes: runtimes("android"), out: File.join(@dir, "dist"), apps: [app]).fetch(app)
    log = File.join(@dir, "gradle.log")
    built = system(File.join(project, "gradlew"), "--no-daemon", "--project-dir", project, "assembleDebug", out: log, err: %i[child out])
    assert built, "Gradle built #{app.name}:\n#{MobileParity::Android.gradle_failure(File.read(log))}"
    apk = Dir.glob(File.join(project, "build", "outputs", "apk", "debug", "*-debug.apk")).first or flunk "Gradle built no debug APK"
    adb("install", "-r", apk)

    assert_said "so", MobileParity::Android.new(work: File.join(@dir, "android"), out: StringIO.new).launch(app)
  ensure
    system("adb", "uninstall", app.identifier, out: File::NULL, err: File::NULL) if ENV["ANDROID_SERIAL"] && app
  end

  # A copy of the fixture named +name+, as a MobileParity::App.
  private def app(name)
    root = File.join(@dir, "apps", name)
    FileUtils.mkdir_p(File.dirname(root))
    FileUtils.cp_r(FIXTURE, root)
    File.write(File.join(root, "fledge.yml"), "name: #{name}\nidentifier: com.setdef.fledge.#{name}\n")
    MobileParity::App.new(path: root, name:, identifier: "com.setdef.fledge.#{name}", prints: /./)
  end

  # That the app said, in what it +logged+ (MobileParity::Logged), that
  # the library answered from the path where a desktop's RubyGems leaves
  # it, whose extension is +dlext+, the phone Ruby's DLEXT.
  private def assert_said(dlext, logged)
    assert_equal ["echoer: HELLO from lib/echoer/libechoer.#{dlext}"], logged.output.grep(/\Aechoer/),
      "the app logged:\n#{logged.output.last(8).join("\n")}"
  end

  # The folder of the runtimes, which holds +phone+'s, as rake runtime
  # writes them.
  private def runtimes(phone)
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    file = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(phone)))
    message = "no #{File.basename(file)} in #{dir}; run bundle exec rake runtime[#{phone}]"
    (phone == "ios") ? ios_missing(message) : android_missing(message) unless File.file?(file)
    dir
  end

  private def adb(*arguments)
    out, status = Open3.capture2e("adb", *arguments)
    assert_predicate status, :success?, "adb #{arguments.join(' ')}:\n#{out}"
    out
  end
end
