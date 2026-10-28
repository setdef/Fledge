# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "mobile"

class RuntimeBuilder
  # iOS and iPadOS: Ruby for devices and for the Simulator, both arm64,
  # built with Xcode's compilers after xord/cruby's Rakefile (at 11d62c4,
  # lines 499 to 724), and packed with Xcode's own tools as an
  # XCFramework of two static libraries, FledgeRuby.xcframework (ADR 011,
  # section 2).
  #
  # Each slice holds libfledgeruby.a (Ruby, its extensions and encodings,
  # OpenSSL, libyaml, and the embedding API, in one archive), its headers
  # with a module map, so Swift imports it as FledgeRuby, and, as
  # CPython's XCFramework for iOS does, the Ruby the slice runs: its
  # lib/ruby and its CA certificates in libexec/, which an app copies into
  # its bundle for the slice it builds.
  class IOS < Mobile
    # What iOS declares in its headers but forbids or lacks, for
    # configure (xord/cruby's Rakefile, line 578): system, syscall,
    # backtrace, getentropy, dup3, and pipe2.
    MISSING = %w[system syscall __syscall backtrace getentropy dup3 pipe2].freeze

    # Writes the stub sys/vnode.h the iOS SDK lacks (RubySource), then
    # builds.
    def build(stage)
      @stub = File.join(@build_dir, "stub")
      RubySource.write_vnode_stub(@stub)
      super
    end

    # fiddle is left out, as xord/cruby leaves it out "to pass the App
    # Store review" (Rakefile, line 577): it would call any C function.
    private def omitted_gems
      %w[fiddle]
    end

    private def edits
      %i[psych_extconf vm_dump ruby_c]
    end

    private def host_triple(_target)
      "aarch64-apple-darwin"
    end

    private def sysroot(target)
      (@sysroots ||= {})[target.sdk] ||= @builder.capture("xcrun", "--sdk", target.sdk, "--show-sdk-path").strip
    end

    private def compiler(target, name = "clang")
      "#{@builder.capture('xcrun', '--sdk', target.sdk, '--find', name).strip} -target #{target.triple} -isysroot #{sysroot(target)}"
    end

    private def environment(target)
      { "CC" => compiler(target), "CXX" => compiler(target, "clang++"), "IPHONEOS_DEPLOYMENT_TARGET" => IOS_MINIMUM }
    end

    # OpenSSL's own iOS targets; the Simulator's needs its own minimum
    # flag, since with -mios-version-min its assembly is tagged for
    # devices and the Simulator's link fails.
    private def openssl_environment(_target)
      { "IPHONEOS_DEPLOYMENT_TARGET" => IOS_MINIMUM }
    end

    private def openssl_options(target)
      [(target.sdk == "iphonesimulator") ? "-mios-simulator-version-min=#{IOS_MINIMUM}" : "-mios-version-min=#{IOS_MINIMUM}"]
    end

    private def target_options(target, _deps)
      [
        "--disable-dln",
        *MISSING.map { |name| "ac_cv_func_#{name}=no" },
        "ac_cv_func_setpgrp_void=yes",
        "CPPFLAGS=-I#{@stub}",
        "CFLAGS=-Os -fvisibility=hidden",
        "LDFLAGS=-framework Security",
      ]
    end

    # One archive per slice, its headers, and the XCFramework of both;
    # then each slice's Ruby beside its library.
    private def package(stage)
      libraries = @roots.to_h { |target, root| [target, library(target, root)] }
      framework = File.join(stage, "FledgeRuby.xcframework")
      @builder.run("xcodebuild", "-create-xcframework",
        *libraries.flat_map { |_target, (library, headers)| ["-library", library, "-headers", headers] }, "-output", framework)
      @roots.each do |target, root|
        slice = File.join(framework, target.slice)
        raise "#{framework} has no slice #{target.slice}" unless File.directory?(slice)

        FileUtils.mkdir_p(File.join(slice, "lib"))
        FileUtils.cp_r(File.join(root, "lib", "ruby"), File.join(slice, "lib", "ruby"))
        copy_certificates(File.join(slice, "libexec"))
      end
    end

    # libfledgeruby.a for +target+: every archive Ruby's build made, the
    # libraries it links, and the embedding API, merged by Apple's libtool,
    # without libruby's dmyext.o and dmyenc.o, which define empty Init_ext
    # and Init_enc for a Ruby without static extensions: the linker would
    # take them before extinit.o's and encinit.o's, and require "json"
    # would fail (seen in the spike; xord/cruby leaves them out too,
    # Rakefile line 686). Debug information is stripped. Returns the
    # library and its headers' folder.
    private def library(target, root)
      folder = File.join(@build_dir, target.name, "package")
      FileUtils.rm_rf(folder)
      FileUtils.mkdir_p(folder)
      objects = compile_api(target, root, folder)
      library = File.join(folder, "libfledgeruby.a")
      @builder.run("xcrun", "libtool", "-static", "-no_warning_for_no_symbols", "-o", library, *@archives.fetch(target), *objects)
      @builder.run("xcrun", "ar", "-d", library, "dmyext.o", "dmyenc.o")
      @builder.run("xcrun", "ranlib", library)
      @builder.run("xcrun", "strip", "-S", library)
      [library, headers(root, folder)]
    end

    # The embedding API (runtime/mobile/fledge_ruby.c) and the system log
    # it writes to (apple.c), compiled for +target+ with the launcher's
    # warnings as errors and under clang's static analyzer.
    private def compile_api(target, root, folder)
      cc = compiler(target).split
      flags = [
        "-std=gnu11",
        "-Os",
        *WARNINGS,
        "-isystem",
        ruby_headers(root),
        "-isystem",
        File.join(ruby_headers(root), "arm64-darwin"),
        "-I",
        MOBILE,
        "-I",
        Recipe::LAUNCHER,
      ]
      api_sources.map do |source|
        object = File.join(folder, "#{File.basename(source, '.c')}.o")
        @builder.run(*cc, "--analyze", "-Xclang", "-analyzer-werror", *flags, source, "-o", File.join(folder, "analysis.plist"))
        @builder.run(*cc, *flags, "-c", source, "-o", object)
        object
      end
    end

    private def api_sources
      [
        File.join(MOBILE, "fledge_ruby.c"),
        File.join(MOBILE, "output.c"),
        File.join(MOBILE, "apple.c"),
        File.join(Recipe::LAUNCHER, "locale.c"),
      ]
    end

    private def ruby_headers(root)
      File.join(root, "include", "ruby-4.0.0")
    end

    # The slice's headers: Ruby's, with its configuration header beside
    # the rest (ruby/config.h), so that one folder on the include path
    # serves #include <ruby.h>, and the embedding API's with its module
    # map.
    private def headers(root, folder)
      headers = File.join(folder, "Headers")
      FileUtils.cp_r(ruby_headers(root), headers)
      arch = File.join(headers, "arm64-darwin")
      FileUtils.cp_r(File.join(arch, "ruby", "."), File.join(headers, "ruby"))
      FileUtils.rm_rf(arch)
      FileUtils.cp([File.join(MOBILE, "fledge_ruby.h"), File.join(MOBILE, "module.modulemap")], headers)
      headers
    end
  end
end
