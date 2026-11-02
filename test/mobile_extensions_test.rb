# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
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
  def setup
    @dir = Dir.mktmpdir
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

  def test_link_flags_keep_libraries_frameworks_and_the_gems_own_archives
    flags = Fledge::MobileExtensions.link_flags("-lz -framework Security -L/opt/x/lib ./libvendored.a -fno-common -lz -Wl,-rpath,. -lc++", dir: "/work/ext")

    assert_equal ["-lz", "-framework", "Security", "-L/opt/x/lib", "/work/ext/libvendored.a", "-lc++"], flags
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
    message = "no #{File.basename(phone)} in #{dir}; run bundle exec rake runtime[#{name}]"
    unless File.file?(phone)
      flunk message if ENV["FLEDGE_REQUIRE_RUNTIME"]
      skip message
    end
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
