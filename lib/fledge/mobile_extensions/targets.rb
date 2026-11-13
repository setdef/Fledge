# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "../command"
require_relative "../error"
require_relative "cmake"
require_relative "rust"

module Fledge
  class MobileExtensions
    # One compiler target: its name (an XCFramework slice, or an Android
    # ABI's platform), the Ruby's architecture, the folder of the
    # runtime's Ruby for it, and the environment for the shim.
    class Target < Data.define(:name, :root, :arch_dir, :libdir, :environment, :abi)
      ##
      # :attr_reader: name
      # <tt>"ios-arm64"</tt>, or <tt>"aarch64-linux-android"</tt>.

      ##
      # :attr_reader: root
      # The runtime's Ruby for the target: an XCFramework slice, or the runtime.

      ##
      # :attr_reader: arch_dir
      # The folder of the target's rbconfig.rb.

      ##
      # :attr_reader: libdir
      # The folder of the library that holds Ruby, which an Android link names.

      ##
      # :attr_reader: environment
      # The shim's variables (SHIM) for the target.

      ##
      # :attr_reader: abi
      # Android's name for the target (<tt>"arm64-v8a"</tt>), or +nil+.
    end

    # Finds the compilers' targets of a phone's runtime: for each, the
    # tools of this computer's Xcode or Android NDK aimed at it, the
    # runtime's Ruby and headers for it, and a CMake toolchain file and
    # Cargo's variables for the same.
    #
    # Use it once for each build, from Fledge::MobileExtensions.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileExtensions::Targets.new(work:).call(tree, nil).map(&:name)
    #   # => ["ios-arm64", "ios-arm64-simulator"]
    #--
    # SPDX-SnippetEnd
    #++
    class Targets
      # The XCFramework's slices, the device's and the Simulator's.
      IOS_SLICES = %w[ios-arm64 ios-arm64-simulator].freeze

      # The Android targets' Ruby architectures, and the ABI Android calls each.
      ANDROID_ABIS = { "aarch64-linux-android" => "arm64-v8a", "x86_64-linux-android" => "x86_64" }.freeze

      # What an Android extension built as a file links with besides
      # mkmf's flags, as the runtime's libfledgeext.so does: LOAD segments
      # aligned for 16 KB pages, which Google Play requires, and the run
      # path of its own folder, so that the ruby program, which runs
      # outside the app's library namespace, finds a library it carries
      # beside it. The quotes and the doubled dollar sign reach the
      # linker through make and the shell as <tt>$ORIGIN</tt>.
      DLDFLAGS = "-Wl,-z,max-page-size=16384 -Wl,-rpath,'$$ORIGIN'"

      # Creates the finder, which writes its toolchain files and unpacks
      # the AAR in +work+, a folder of the build's own.
      def initialize(work:)
        @work = work
      end

      # The targets of the runtime unpacked at +tree+: Android's ABIs,
      # compiled with +ndk+, or, when +ndk+ is +nil+, the iOS slices.
      def call(tree, ndk)
        if ndk
          aar = unpack_aar(File.join(tree, "FledgeRuby.aar"))
          ANDROID_ABIS.map { |arch, abi| android_target(arch, abi, tree, aar, ndk) }
        else
          IOS_SLICES.map { |slice| ios_target(slice, File.join(tree, "FledgeRuby.xcframework", slice)) }
        end
      end

      # The slice's tools: Xcode's clang for the slice's SDK, aimed at the
      # triple the runtime was built for (which its rbconfig.rb records),
      # the slice's headers, which sit beside its library and not where
      # rbconfig.rb says, and a CMake toolchain file for the same.
      private def ios_target(slice, root)
        sdk = slice.end_with?("-simulator") ? "iphonesimulator" : "iphoneos"
        arch_dir = rbconfig_dir(root)
        triple = recorded_compiler(arch_dir)[/-target (\S+)/, 1] or raise Error, "#{arch_dir}/rbconfig.rb records no target triple"
        sysroot = xcrun(sdk, "--show-sdk-path")
        cc = xcrun(sdk, "--find", "clang")
        cxx = xcrun(sdk, "--find", "clang++")
        environment = {
          "FLEDGE_CC" => "#{cc} -target #{triple} -isysroot #{sysroot}",
          "FLEDGE_CXX" => "#{cxx} -target #{triple} -isysroot #{sysroot}",
          "FLEDGE_HEADERS" => File.join(root, "Headers"),
          "FLEDGE_LIBRUBYARG" => "-L#{root} -lfledgeruby -lz $(MAINLIBS) -framework Security -framework CoreFoundation",
          "CMAKE_TOOLCHAIN_FILE" => toolchain_file(slice, CMake.ios(triple:, sysroot:, cc:, cxx:)),
          **Rust.ios(slice, triple:, sysroot:),
        }
        Target.new(name: slice, root:, arch_dir:, libdir: root, environment: with_tools(environment), abi: nil)
      end

      # The ABI's tools: the NDK's clang of the very name the runtime was
      # built with, its llvm-ar and llvm-ranlib, the library that holds
      # Ruby, from the AAR, and a CMake toolchain file for the same.
      private def android_target(arch, abi, tree, aar, ndk)
        arch_dir = File.join(tree, "lib", "ruby", Dir.children(File.join(tree, "lib", "ruby")).grep(/\A\d/).first.to_s, arch)
        compiler = File.basename(recorded_compiler(arch_dir))
        cc = File.join(ndk.bin, compiler)
        raise Error, "#{ndk.root} has no #{compiler}, which Android's Ruby was built with" unless File.file?(cc)

        libdir = File.join(aar, "jni", abi)
        environment = {
          "FLEDGE_CC" => cc,
          "FLEDGE_CXX" => "#{cc}++",
          "FLEDGE_AR" => File.join(ndk.bin, "llvm-ar"),
          "FLEDGE_RANLIB" => File.join(ndk.bin, "llvm-ranlib"),
          "FLEDGE_LIBRUBYARG" => "-L#{libdir} -lfledgeruby",
          "FLEDGE_DLDFLAGS" => DLDFLAGS,
          "FLEDGE_LDSHAREDXX" => "$(CXX) -shared -static-libstdc++",
          "CMAKE_TOOLCHAIN_FILE" => toolchain_file(arch, CMake.android(ndk: ndk.root, abi:, compiler:)),
          **Rust.android(arch, bin: ndk.bin, cc:, resource: resource_dir(cc, ndk)),
        }
        Target.new(name: arch, root: tree, arch_dir:, libdir:, environment: with_tools(environment), abi:)
      end

      # +environment+, a target's, with the phone's tools also under the
      # names autoconf and make read, CC, CXX, AR, and RANLIB, in place of
      # the developer's (FOREIGN), so that a build an extension's Makefile
      # starts is aimed at the phone too: the ffi gem's runs libffi's
      # configure with no compiler of its own on Android
      # (<tt>ext/ffi_c/libffi.mk</tt> at 1.17.4), as a cross build's
      # environment names the target's compiler for rake-compiler-dock and
      # crossenv. And no pkg-config, as the runtime's own configure is
      # given none (PKG_CONFIG=false): pkg-config finds this computer's
      # libraries, not the phone's, and mkmf runs it, where the phone's
      # rbconfig.rb names none, as the environment's PKG_CONFIG names it
      # (<tt>lib/mkmf.rb</tt>, line 1969 at Ruby 4.1.0-preview1). It found
      # a Mac's libffi for the ffi gem, whose extconf.rb then linked the
      # Simulator's with <tt>-lffi</tt>. A gem's
      # <tt>--with-pkg-config</tt> option still names one.
      private def with_tools(environment)
        tools = %w[CC CXX AR RANLIB].to_h { |name| [name, environment["FLEDGE_#{name}"]] }.compact
        environment.merge(tools, "PKG_CONFIG" => "false")
      end

      # The resource folder of the NDK's compiler +cc+, which holds the
      # headers it brings itself (<tt>stdarg.h</tt> and the rest).
      private def resource_dir(cc, ndk)
        Command.run(cc, "-print-resource-dir", install: "Install the Android NDK again: #{ndk.root} has no working #{File.basename(cc)}.").strip
      end

      # Writes +text+, the CMake toolchain file of the target +name+, into
      # the build's folder, and returns its path.
      private def toolchain_file(name, text)
        path = File.join(@work, "toolchains", "#{name}.cmake")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, text)
        path
      end

      private def xcrun(sdk, *)
        Command.run("xcrun", "--sdk", sdk, *, install: INSTALL_XCODE).strip
      end

      # The folder of the rbconfig.rb under +root+'s lib/ruby.
      private def rbconfig_dir(root)
        path = Dir.glob(File.join(root, "lib", "ruby", "*", "*", "rbconfig.rb")).first or raise Error, "#{root} holds no Ruby for a phone: no rbconfig.rb"
        File.dirname(path)
      end

      # The compiler the rbconfig.rb in +arch_dir+ records.
      private def recorded_compiler(arch_dir)
        path = File.join(arch_dir, "rbconfig.rb")
        File.read(path)[/CONFIG\["CC"\] = "([^"]+)"/, 1] or raise Error, "#{path} records no compiler"
      end

      # The AAR's contents, unpacked once with unzip (an AAR is a zip).
      private def unpack_aar(aar)
        into = File.join(@work, "aar")
        return into if File.directory?(File.join(into, "jni"))

        FileUtils.mkdir_p(into)
        Command.run("unzip", "-q", "-o", aar, "-d", into, install: "Install unzip, which unpacks the Android runtime's AAR.")
        into
      end
    end
  end
end
