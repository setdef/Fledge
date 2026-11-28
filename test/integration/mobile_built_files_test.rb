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

# What a phone app carries of the files a gem's build left in the gem's
# folder: a path gem whose extconf.rb writes data outside its
# require paths, which its Ruby reads by its path, as under bundle exec,
# where RubyGems leaves the gem's folder as the build left it. fledge
# build writes the app's Xcode or Gradle project, Xcode or Gradle builds
# it, and it runs on the iOS Simulator or the attached Android device as
# tasks/mobile_parity.rb runs the examples. Without the runtime, the
# tools, or a Simulator or device they skip, and fail instead where
# FLEDGE_REQUIRE_IOS or FLEDGE_REQUIRE_ANDROID is set.
class MobileBuiltFilesTest < Minitest::Test
  include AndroidRequired
  include IOSRequired

  # The gem: its extension says hello, and its extconf.rb writes
  # data/table.txt beside the gem's root, the same for every target.
  GEM = {
    "ext/tabled/extconf.rb" => <<~RUBY,
      require "mkmf"
      require "fileutils"
      FileUtils.mkdir_p(File.join(__dir__, "../../data"))
      File.write(File.join(__dir__, "../../data/table.txt"), "from the build\\n")
      create_makefile("tabled/tabled")
    RUBY
    "ext/tabled/tabled.c" => <<~C,
      #include <ruby.h>
      static VALUE hello(VALUE self) { return rb_str_new_cstr("hello"); }
      void Init_tabled(void) { rb_define_module_function(rb_define_module("Tabled"), "hello", hello, 0); }
    C
    "lib/tabled.rb" => "require \"tabled/tabled\"\n\nmodule Tabled\n  TABLE = File.read(File.expand_path(\"../data/table.txt\", __dir__))\nend\n",
  }.freeze

  # The Android app's gem, in place of GEM's files: its extconf.rb also
  # writes data/arch.txt, the architecture of the Ruby it builds for,
  # each target's own, and its Ruby reads that too.
  OWN = {
    "ext/tabled/extconf.rb" => GEM.fetch("ext/tabled/extconf.rb").sub("create_makefile", <<~RUBY.chomp),
      File.write(File.join(__dir__, "../../data/arch.txt"), RbConfig::CONFIG["arch"])
      create_makefile
    RUBY
    "lib/tabled.rb" => GEM.fetch("lib/tabled.rb").sub("end\n", "  ARCH = File.read(File.expand_path(\"../data/arch.txt\", __dir__))\nend\n"),
  }.freeze

  # What the app prints with the data its gem's build wrote.
  SAYS = ["tabled says hello and reads from the build"].freeze

  # What the Android app prints with the data its gem's build wrote,
  # alike and for its own target.
  SAYS_OWN = ["tabled says hello and reads from the build for its own target"].freeze

  def setup
    @dir = Fledge::LongPath.of(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_an_ios_app_carries_the_data_its_gems_build_wrote_for_every_slice_alike
    ios_missing("Xcode builds an iOS app on a Mac only") unless Fledge::Platform.local.name == "arm64-darwin"
    runtimes = runtimes("ios")
    app = app("BuiltDataIOS")
    project = MobileParity.projects("ios", runtimes:, out: File.join(@dir, "dist"), apps: [app]).fetch(app)
    FileUtils.mkdir_p(File.join(@dir, "ios"))
    ios = MobileParity::IOS.new(runtimes:, work: File.join(@dir, "ios"), out: StringIO.new)
    bundle = ios.build_app(app, project)
    printed = nil
    ios.on_simulator("iPhone", { app => bundle }) { |_, logged, _| printed = logged }

    refute_nil printed, "the Simulator ran #{app.name}"
    assert_said printed
    assert_carried project
  end

  def test_an_android_app_carries_the_data_its_gems_build_wrote_alike_and_for_each_abi
    android_missing("no Android device or emulator: set ANDROID_SERIAL, as bin/android-emulator does") unless ENV["ANDROID_SERIAL"]
    app = app("BuiltDataAndroid", own: true)
    project = MobileParity.projects("android", runtimes: runtimes("android"), out: File.join(@dir, "dist"), apps: [app]).fetch(app)
    log = File.join(@dir, "gradle.log")
    built = system(File.join(project, "gradlew"), "--no-daemon", "--project-dir", project, "assembleDebug", out: log, err: %i[child out])
    assert built, "Gradle built #{app.name}:\n#{MobileParity::Android.gradle_failure(File.read(log))}"
    apk = Dir.glob(File.join(project, "build", "outputs", "apk", "debug", "*-debug.apk")).first or flunk "Gradle built no debug APK"
    adb("install", "-r", apk)

    assert_said MobileParity::Android.new(work: File.join(@dir, "android"), out: StringIO.new).launch(app), SAYS_OWN
    assert_carried project
    assert_carried_apart project
  ensure
    system("adb", "uninstall", app.identifier, out: File::NULL, err: File::NULL) if ENV["ANDROID_SERIAL"] && app
  end

  # The gem's folder in +project+'s Ruby root holds the data, and none of
  # what each target's build wrote for itself: its Makefile, which names
  # the target's compiler, and its objects.
  private def assert_carried(project)
    folder = File.join(project, "fledge", "app", "tabled")
    assert_equal "from the build\n", File.read(File.join(folder, "data", "table.txt"))
    refute_path_exists File.join(folder, "ext", "tabled", "Makefile"), "each target's Makefile is its own"
    assert_empty Dir.glob("**/*.o", base: folder), "a phone carries no compiled code among a gem's files"
  end

  # +project+'s Ruby root holds, for each ABI, what that ABI's build left
  # for itself, the data and the Makefile, under .fledge-abi/ABI/, and
  # lists it in fledge.files.
  private def assert_carried_apart(project)
    root = File.join(project, "fledge")
    Fledge::MobileExtensions::Targets::ANDROID_ABIS.each_value do |abi|
      folder = File.join(root, ".fledge-abi", abi, "app", "tabled")
      assert_includes File.read(File.join(folder, "data", "arch.txt")), "android"
      assert_path_exists File.join(folder, "ext", "tabled", "Makefile")
      assert_includes File.read(File.join(root, "fledge.files")), "#{abi}\tapp/tabled/data/arch.txt\n"
    end
  end

  # A developer's app +name+ with the path gem tabled in its folder,
  # locked for the ruby platform, whose program prints what the gem's
  # extension and data say, as a MobileParity::App; with +own+, data its
  # build writes for each target too (OWN).
  private def app(name, own: false)
    root = File.join(@dir, "apps", name)
    files = GEM.merge(own ? OWN : {})
    files.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(root, "tabled", path)))
      File.write(File.join(root, "tabled", path), text)
    end
    File.write(File.join(root, "tabled", "tabled.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = "tabled"
        spec.version = "1.0.0"
        spec.authors = ["Kerrick Long"]
        spec.summary = "A gem whose extconf.rb writes data its Ruby reads"
        spec.files = #{files.keys.inspect}
        spec.extensions = ["ext/tabled/extconf.rb"]
      end
    RUBY
    File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n\ngem \"tabled\", path: \"tabled\"\n")
    File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
      PATH
        remote: tabled
        specs:
          tabled (1.0.0)

      GEM
        remote: https://rubygems.org/
        specs:

      PLATFORMS
        ruby

      DEPENDENCIES
        tabled!

      CHECKSUMS
        bundler (4.0.20) sha256=7978a8ac648767f5e635bc522445b79e80a52b907a39a36c2d8085ed6bc762ae
        tabled (1.0.0)

      BUNDLED WITH
        4.0.20
    LOCK
    File.write(File.join(root, "fledge.yml"), "name: #{name}\nidentifier: com.setdef.fledge.#{name}\n")
    target = " for \#{(Tabled::ARCH == RbConfig::CONFIG['arch']) ? 'its own target' : Tabled::ARCH}" if own
    File.write(File.join(root, "main.rb"), "require \"tabled\"\nputs \"tabled says \#{Tabled.hello} and reads \#{Tabled::TABLE.strip}#{target}\"\n")
    MobileParity::App.new(path: root, name:, identifier: "com.setdef.fledge.#{name}", prints: /./)
  end

  # That the app said +says+ in what it +logged+ (MobileParity::Logged),
  # without the host's own lines.
  private def assert_said(logged, says = SAYS)
    assert_equal says, logged.output.grep(/\Atabled/), "the app logged:\n#{logged.output.last(8).join("\n")}"
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
