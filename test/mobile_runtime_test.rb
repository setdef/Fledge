# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/runtime_builder"
require "rubygems/package"
require "zlib"

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

    %w[ruby openssl libyaml libffi ca-certificates gradle xcodegen bundletool].each do |name|
      assert_match(%r{\Ahttps://}, pins.fetch(name).fetch("url"), name)
      assert_match(/\A\h{64}\z/, pins.fetch(name).fetch("sha256"), name)
    end
    assert_equal %w[arm64-darwin x86_64-linux], pins.fetch("ndk").fetch("hosts").keys.sort
    assert_equal "4.1.0-preview1", pins.fetch("ruby").fetch("version")
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

  # Android's seccomp filter for apps stops a process that calls setgid,
  # setuid, setregid, setreuid, setresgid, or setgroups, and lets it call
  # setresuid (bionic, libc/SECCOMP_BLOCKLIST_APP.TXT, at 731631f);
  # bionic's setegid calls setresgid, and its initgroups setgroups.
  # configure finds each, as on Linux, and process.c calls its own in
  # their place, which answer as Linux answers a process without
  # CAP_SETGID or CAP_SETUID: Process.egid= with the current group ID
  # succeeds and with another raises EPERM, where the app would end or
  # NotImplementedError rise.
  def test_android_ruby_answers_each_id_call_the_seccomp_filter_stops
    assert_empty RuntimeBuilder::Android::CONFIGURE.grep(/\Aac_cv_func_/)
    assert_includes RuntimeBuilder::Android.allocate.__send__(:edits), :process_c_ids
    edited = RuntimeBuilder::RubySource.process_c_ids("#include \"hrtime.h\"\n#include \"internal.h\"\n#ifndef WTERMSIG\n")

    %w[setgid setegid setregid setresgid setgroups initgroups setuid setreuid].each do |call|
      assert_includes edited, "#define #{call} fledge_#{call}\n"
    end
    assert_match(/fledge_setgid\(gid_t gid\)\n\{.*?if \(gid != r && gid != s\) return fledge_refuse\(\);/m, edited)
    assert_match(/fledge_setgroups\(size_t size, const gid_t \*list\)\n\{.*?return fledge_refuse\(\);/m, edited)
    assert_match(/fledge_setuid\(uid_t uid\)\n\{.*?return setresuid\(\(uid_t\)-1, uid, \(uid_t\)-1\);/m, edited)
    assert edited.end_with?("#define setuid fledge_setuid\n#endif\n#ifndef WTERMSIG\n")
    assert_raises(RuntimeError) { RuntimeBuilder::RubySource.process_c_ids("#include \"internal.h\"\n") }
  end

  # A phone's Ruby, as a musl runtime's, finds its CA certificates as
  # rv-ruby's Ruby does: OpenSSL reads them from a variable of rv-ruby's
  # name, which openssl.rb sets as openssl loads, to SSL_CERT_FILE or
  # else to libexec/cert.pem beside the Ruby, so ENV holds nothing of the
  # runtime's before require "openssl" and the same after it as under
  # rv-ruby's ruby main.rb.
  def test_a_built_ruby_finds_its_certificates_as_rv_rubys_does
    Dir.mktmpdir do |dir|
      header = File.join(dir, "openssl", "include", "internal", "common.h")
      FileUtils.mkdir_p(File.dirname(header))
      File.write(header, "# define X509_CERT_FILE_EVP \"SSL_CERT_FILE\"\n")
      ruby = File.join(dir, "root", "lib", "ruby")
      FileUtils.mkdir_p(File.join(ruby, "4.1.0"))
      File.write(File.join(ruby, "4.1.0", "openssl.rb"), "require 'openssl.so'\n")

      RuntimeBuilder::Certificates.rename_variable(File.join(dir, "openssl"))
      RuntimeBuilder::Certificates.point_openssl_rb(ruby)

      assert_equal "# define X509_CERT_FILE_EVP \"PORTABLE_RUBY_SSL_CERT_FILE\"\n", File.read(header)
      set, load = File.readlines(File.join(ruby, "4.1.0", "openssl.rb"), chomp: true)
      assert_equal "require 'openssl.so'", load
      script = File.join(dir, "set.rb")
      File.write(script, "RbConfig.singleton_class.define_method(:ruby) { #{File.join(dir, 'root', 'bin', 'ruby').dump} }\n" \
        "#{set}\nprint ENV.fetch('PORTABLE_RUBY_SSL_CERT_FILE')")
      named = -> (value) { IO.popen({ "SSL_CERT_FILE" => value }, [RbConfig.ruby, script], &:read) }
      assert_equal File.join(dir, "root", "libexec", "cert.pem"), named.call(nil)
      assert_equal "/elsewhere.pem", named.call("/elsewhere.pem")
      assert_raises(RuntimeError) { RuntimeBuilder::Certificates.rename_variable(File.join(dir, "openssl")) }
    end
  end

  def test_platform_finds_desktop_and_mobile_runtimes_by_name
    assert_equal Fledge::Platform.find("x86_64-linux"), RuntimeBuilder.platform("x86_64-linux")
    assert_equal "android", RuntimeBuilder.platform("android").name
    assert_raises(Fledge::UsageError) { RuntimeBuilder.platform("arm64-ios") }
  end

  # The phone runtimes' statuses are frozen for 1.x
  # (doc/contributors/design/public-interface.md, "Frozen for 1.x"), and
  # are sysexits' values as the desktop launcher's are.
  def test_the_phone_runtimes_statuses_are_the_launchers
    root = File.expand_path("..", __dir__)
    phone = File.read(File.join(root, "runtime", "mobile", "fledge_ruby.h"))
    launcher = File.read(File.join(root, "runtime", "launcher", "launcher.h"))
    values = -> (text, name) { Integer(text[/\b#{name} = (\d+)/, 1]) }

    assert_equal [66, 70], [values.call(phone, "FLEDGE_RUBY_NO_APP"), values.call(phone, "FLEDGE_RUBY_SOFTWARE")]
    assert_equal [66, 70], [values.call(launcher, "FLEDGE_EXIT_NO_APP"), values.call(launcher, "FLEDGE_EXIT_SOFTWARE")]
  end

  # A phone's Ruby is built in its source folder, as rv-ruby builds a
  # desktop's, so that its default gems' specifications list the files a
  # desktop's do (doc/contributors/design/phone-runtimes.md, "Building
  # Ruby for a phone"). Built beside its source, tool/rbinstall.rb put
  # lib/ before each extconf.rb a gemspec lists, and RubyGems'
  # register_default_spec then took io-nonblock for a gem whose files sit
  # under lib/ and left out io/nonblock.bundle, so require "io/nonblock"
  # did not activate the gem; bundler's listed none of its manual pages.
  # These read the runtimes rake runtime[ios] and runtime[android] write,
  # and skip without them.
  def test_an_ios_runtimes_default_gems_list_their_files_as_a_desktops_do
    assert_default_gems_list_their_files_as_a_desktops_do("ios")
  end

  def test_an_android_runtimes_default_gems_list_their_files_as_a_desktops_do
    assert_default_gems_list_their_files_as_a_desktops_do("android")
  end

  def assert_default_gems_list_their_files_as_a_desktops_do(name)
    slices = default_specifications(name)
    assert_equal mobile(name).targets.size, slices.size, slices.keys.inspect
    slices.each do |slice, specs|
      nonblock = specs.fetch("io-nonblock").files
      assert_includes nonblock, "ext/io/nonblock/extconf.rb", slice
      assert_empty nonblock.grep(%r{\Alib/}), slice
      assert nonblock.any? { |file| file.match?(%r{\Aio/nonblock\.(?:bundle|so)\z}) }, "#{slice}: #{nonblock.inspect}"
      assert_includes specs.fetch("bundler").files, "lib/bundler/man/bundle.1", slice
      specs.each { |gem, spec| assert_empty spec.files.grep(%r{\Alib/ext/}), "#{slice}: #{gem}" }
    end
  end

  # The default gems' specifications in the phone runtime +name+ that
  # tmp/runtime (or FLEDGE_RUNTIME_DIR) holds, by gem name, for each
  # folder of the runtime that holds a Ruby.
  def default_specifications(name)
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
    archive = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find(name)))
    skip "no #{File.basename(archive)} in #{dir}; run bundle exec rake runtime[#{name}]" unless File.file?(archive)

    slices = Hash.new { |hash, key| hash[key] = {} }
    Dir.mktmpdir do |work|
      Zlib::GzipReader.open(archive) do |gzip|
        Gem::Package::TarReader.new(gzip).each.with_index do |entry, index|
          slice, file = entry.full_name.match(%r{\A(.*)/lib/ruby/gems/[^/]+/specifications/default/([^/]+\.gemspec)\z})&.captures
          next unless file

          path = File.join(work, "#{index}-#{file}")
          File.binwrite(path, entry.read)
          spec = Gem::Specification.load(path) or flunk "#{entry.full_name} is no gemspec"
          slices[slice][spec.name] = spec
        end
      end
    end
    slices
  end
end
