# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# The parts of the mobile runtimes (ADR 099) that need no Xcode or NDK:
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

  # A mobile runtime ships no LGPL library, so its release carries the
  # runtime, its SBOM, and its NOTICES.
  def test_a_release_publishes_each_mobile_runtime_with_its_sbom_and_notices
    assets = RuntimeBuilder.release_assets(version: "1.2.3")

    %w[ios android].each do |name|
      assert_includes assets, "fledge-runtime-1.2.3-#{name}.tar.gz"
      assert_includes assets, "fledge-runtime-1.2.3-#{name}.spdx.json"
      assert_includes assets, "fledge-runtime-1.2.3-#{name}-NOTICES.txt"
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
  # The Android runtime keeps the wrappers RubyGems wrote for its gems'
  # commands in bin/, as a desktop runtime does, where fledge build finds
  # them (RuntimeContents#binaries), and leaves out the ruby program
  # make install put beside them: the runtime's is libfledgerubyexe.so,
  # and an app links bin/ruby to it as it starts.
  def test_android_keeps_its_gems_commands_but_not_make_installs_ruby
    Dir.mktmpdir do |dir|
      roots = %w[aarch64 x86_64].to_h do |arch|
        root = File.join(dir, arch)
        FileUtils.mkdir_p([File.join(root, "bin"), File.join(root, "lib", "ruby", "4.1.0+5", "#{arch}-linux-android"), File.join(root, "include")])
        File.write(File.join(root, "bin", "ruby"), "ELF #{arch}")
        File.write(File.join(root, "bin", "rake"), "#!/bin/sh\n# rake's wrapper\n")
        File.write(File.join(root, "lib", "ruby", "4.1.0+5", "#{arch}-linux-android", "rbconfig.rb"), arch)
        [arch, root]
      end
      builder = RuntimeBuilder::Android.allocate
      builder.instance_variable_set(:@roots, roots)
      stage = File.join(dir, "stage")

      builder.__send__(:merge_trees, stage)

      assert_equal ["rake"], Dir.children(File.join(stage, "bin"))
      assert_equal "#!/bin/sh\n# rake's wrapper\n", File.read(File.join(stage, "bin", "rake"))
      assert_path_exists File.join(stage, "lib", "ruby", "4.1.0+5", "x86_64-linux-android", "rbconfig.rb")
    end
  end

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

  # Android lets an app write code and run it, so its Ruby has YJIT and
  # ZJIT, as a desktop's does, compiled by rustc for each target and
  # taken into libruby by the NDK's linker and objcopy, not the build
  # machine's. iOS gives an app no such memory, so its Ruby has no JIT.
  def test_android_ruby_has_yjit_and_zjit_as_a_desktops_does_and_ios_ruby_none
    arm, intel = mobile("android").targets

    assert_equal [
      "--enable-yjit",
      "--enable-zjit",
      "rustc_flags=--target=aarch64-linux-android",
      "LD=/ndk/bin/ld.lld",
      "OBJCOPY=/ndk/bin/llvm-objcopy",
], RuntimeBuilder::Android.jit_options(arm, "/ndk/bin")
    assert_includes RuntimeBuilder::Android.jit_options(intel, "/ndk/bin"), "rustc_flags=--target=x86_64-linux-android"
    assert_equal %w[--disable-yjit --disable-zjit], RuntimeBuilder::Mobile::NO_JIT
    refute RuntimeBuilder::IOS.method_defined?(:jit_options, false) || RuntimeBuilder::IOS.private_method_defined?(:jit_options, false)
  end

  # The builtin binary the build machine's miniruby writes holds the
  # builtins it loaded, and a Ruby without YJIT never loads yjit.rb,
  # which a Ruby with YJIT then cannot find at boot ("[BUG]
  # builtin_lookup: can not find yjit"), so that miniruby is built with
  # the target's JITs, and the build stops where configure chose others.
  def test_the_build_machines_miniruby_has_the_targets_jits
    assert_equal RuntimeBuilder::Android::JITS, RuntimeBuilder::Android.allocate.__send__(:jits)
    assert_equal RuntimeBuilder::Android::JITS, RuntimeBuilder::Android.jit_options(mobile("android").targets.first, "/ndk/bin").first(2)
    assert_equal RuntimeBuilder::Mobile::NO_JIT, RuntimeBuilder::IOS.allocate.__send__(:jits)
    Dir.mktmpdir do |dir|
      makefile = File.join(dir, "Makefile")
      File.write(makefile, "RUSTC = rustc\nYJIT_SUPPORT=yes\nYJIT_LIBS=target/release/libyjit.a\nZJIT_SUPPORT=no\n")

      assert_equal({ "YJIT_SUPPORT" => "yes", "ZJIT_SUPPORT" => "no" }, RuntimeBuilder::Mobile.jits_built(makefile))
      File.write(makefile, "YJIT_SUPPORT=no\n")
      assert_raises(RuntimeError) { RuntimeBuilder::Mobile.jits_built(makefile) }
    end
  end

  # A phone's Ruby lists the gems rv-ruby's desktop Ruby does, which
  # leaves out win32-registry, a gem only Windows can load: pruned as a
  # gem no standard Ruby installs, it goes with its specification.
  def test_a_phones_ruby_leaves_out_the_windows_only_bundled_gem
    Dir.mktmpdir do |ruby|
      gems = File.join(ruby, "gems", "4.1.0+5")
      FileUtils.mkdir_p([File.join(gems, "specifications"), File.join(gems, "gems", "win32-registry-0.1.2")])
      %w[win32-registry-0.1.2 csv-3.3.5].each do |full|
        name, version = full.split(/-(?=\d)/)
        File.write(File.join(gems, "specifications", "#{full}.gemspec"), Gem::Specification.new(name, version).to_ruby)
      end

      RuntimeBuilder::Pruning.prune(ruby, %w[csv win32-registry] - RuntimeBuilder::Mobile::WINDOWS_GEMS)

      assert_equal ["csv-3.3.5.gemspec"], Dir.children(File.join(gems, "specifications"))
      refute_path_exists File.join(gems, "gems", "win32-registry-0.1.2")
    end
  end

  # iOS's Ruby is a dynamic library, as Android's is, and links each
  # extension as one too (-dynamiclib, not the -bundle iOS takes in no
  # framework), with room in its header for the install name its
  # framework gets; Ruby loads each with dlopen.
  def test_ios_ruby_is_shared_and_its_extensions_are_dynamic_libraries_it_loads
    ios = RuntimeBuilder::IOS.allocate
    options = ios.__send__(:target_options, nil, { libffi: "/ffi" })

    assert_includes options, "LDSHARED=$(CC) -dynamiclib -Wl,-headerpad_max_install_names"
    refute_includes options, "--disable-dln"
  end

  # A shared Ruby's install puts its library at libdir/LIBRUBY_SO, which
  # RbConfig names and ruby/spec looks for, as Android's line names its
  # libfledgeruby.so there; on iOS the library is FledgeRuby.framework,
  # so the line names that framework. An install that put no library
  # there is refused, not listed.
  def test_ios_lists_rubys_library_where_rubys_install_put_it
    Dir.mktmpdir do |root|
      ios = RuntimeBuilder::IOS.allocate
      error = assert_raises(RuntimeError) { ios.__send__(:library_line, root) }
      assert_equal "#{root} has no lib/libfledgeruby.dylib, which a shared Ruby's install puts at libdir/LIBRUBY_SO", error.message

      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib", "libfledgeruby.dylib"), "")

      assert_equal "FledgeRuby\tlib/libfledgeruby.dylib\n", ios.__send__(:library_line, root)
    end
  end

  # Ruby's dln.c finds an extension's Init function with dlsym, so the
  # function must be exported, as a desktop's extensions export theirs.
  # configure hides libruby's own names itself, through XCFLAGS, which
  # extensions do not take; a -fvisibility=hidden in CFLAGS would hide
  # every extension's Init function too.
  def test_ios_extensions_keep_their_init_functions_visible
    options = RuntimeBuilder::IOS.allocate.__send__(:target_options, nil, { libffi: "/ffi" })

    assert_includes options, "CFLAGS=-Os"
    assert_empty options.grep(/visibility/)
  end

  # Each extension's framework is named for the feature Ruby requires
  # it by, as CPython names each module's framework for its dotted name,
  # wherever under lib/ruby the extension is installed: a bundled gem's
  # is installed twice, and both copies are one framework.
  def test_each_ios_extensions_framework_is_named_for_its_feature
    assert_equal "fledgerubyext.json.ext.parser.bundle", RuntimeBuilder::IOS.extension_name("4.1.0/arm64-darwin/json/ext/parser.bundle")
    assert_equal ["fledgerubyext.racc.cparse.bundle"] * 2,
      ["gems/4.1.0/gems/racc-1.8.1/lib/racc/cparse.bundle", "gems/4.1.0/extensions/arm64-darwin/4.1.0/racc-1.8.1/racc/cparse.bundle"]
        .map { |path| RuntimeBuilder::IOS.extension_name(path) }
    assert_equal "fledgerubyext.io.nonblock.bundle", RuntimeBuilder::IOS.extension_name("4.1.0/arm64-darwin/io/nonblock.bundle")
    error = assert_raises(RuntimeError) { RuntimeBuilder::IOS.extension_name("site_ruby/thing.bundle") }
    assert_equal "lib/ruby/site_ruby/thing.bundle is in no folder Ruby requires an extension from", error.message
  end

  # configure is told iOS lacks only what its SDK forbids or lacks;
  # backtrace is in the SDK, so a [BUG] report lists the C frames.
  def test_ios_ruby_keeps_backtrace_for_its_crash_reports
    assert_equal %w[system syscall __syscall getentropy dup3 pipe2], RuntimeBuilder::IOS::MISSING
  end

  def test_platform_finds_desktop_and_mobile_runtimes_by_name
    assert_equal Fledge::Platform.find("x86_64-linux"), RuntimeBuilder.platform("x86_64-linux")
    assert_equal "android", RuntimeBuilder.platform("android").name
    assert_raises(Fledge::UsageError) { RuntimeBuilder.platform("arm64-ios") }
  end

  # The phone runtimes' statuses are frozen for 1.x, and
  # are sysexits' values as the desktop launcher's are.
  def test_the_phone_runtimes_statuses_are_the_launchers
    root = File.expand_path("..", __dir__)
    phone = File.read(File.join(root, "runtime", "mobile", "fledge_ruby.h"))
    launcher = File.read(File.join(root, "runtime", "launcher", "launcher.h"))
    values = -> (text, name) { Integer(text[/\b#{name} = (\d+)/, 1]) }

    assert_equal [66, 70], [values.call(phone, "FLEDGE_RUBY_NO_APP"), values.call(phone, "FLEDGE_RUBY_SOFTWARE")]
    assert_equal [66, 70], [values.call(launcher, "FLEDGE_EXIT_NO_APP"), values.call(launcher, "FLEDGE_EXIT_SOFTWARE")]
  end
end
