# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"

module Fledge
  class MobileExtensions
    # The CMake toolchain file of each target of a phone (ADR 027).
    #
    # A gem's <tt>extconf.rb</tt> may run CMake to build a library before
    # mkmf builds the extension over it. CMake cross-compiles from a
    # toolchain file, and reads one from the <tt>CMAKE_TOOLCHAIN_FILE</tt>
    # environment variable when a build folder is new (CMake 3.21 and
    # later), so Fledge writes one for each target and puts it there, as
    # cibuildwheel does for a Python package's build on Android. The
    # <tt>extconf.rb</tt> runs <tt>cmake</tt> as it would on a desktop.
    #
    # For an iOS slice the file sets CMake's own iOS variables to the
    # slice's SDK, processor, and deployment target, with the compilers
    # mkmf is given; for an Android ABI it includes the NDK's own
    # <tt>android.toolchain.cmake</tt>, given the ABI and API level, as
    # Gradle does.
    #
    # Use CMake.ios and CMake.android for the text, and write it once for
    # each target.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileExtensions::CMake.android(ndk: "/sdk/ndk/30.0.16248370", abi: "x86_64", compiler: "x86_64-linux-android26-clang")
    #   # => "...set(ANDROID_ABI x86_64)\nset(ANDROID_PLATFORM android-26)\ninclude(\"/sdk/ndk/30.0.16248370/build/cmake/android.toolchain.cmake\")\n"
    #--
    # SPDX-SnippetEnd
    #++
    module CMake
      # What begins every toolchain file Fledge writes.
      HEADER = <<~CMAKE
        # Written by fledge build (ADR 027) for one target of a phone: CMake
        # reads it from CMAKE_TOOLCHAIN_FILE when an extconf.rb configures a
        # new build folder.
      CMAKE

      # The toolchain file for the iOS slice whose clang target is
      # +triple+ (<tt>arm64-apple-ios15.0-simulator</tt>, which the slice's
      # <tt>rbconfig.rb</tt> records), with the SDK at +sysroot+ and the
      # compilers +cc+ and +cxx+, which also compile Objective-C and
      # Objective-C++. Raises Fledge::Error for a triple that is not iOS's.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::CMake.ios(triple: "arm64-apple-ios15.0", sysroot: sdk, cc: clang, cxx: clangxx)
      #   # => "...set(CMAKE_SYSTEM_NAME iOS)\n..."
      #--
      # SPDX-SnippetEnd
      #++
      def self.ios(triple:, sysroot:, cc:, cxx:)
        match = /\A(?<arch>[^-]+)-apple-ios(?<version>[\d.]+)(?:-simulator)?\z/.match(triple) or
          raise Error, "#{triple} is not a target triple of iOS"
        HEADER + <<~CMAKE
          set(CMAKE_SYSTEM_NAME iOS)
          set(CMAKE_OSX_SYSROOT #{string(sysroot)})
          set(CMAKE_OSX_ARCHITECTURES #{match[:arch]})
          set(CMAKE_OSX_DEPLOYMENT_TARGET #{match[:version]})
          set(CMAKE_C_COMPILER #{string(cc)})
          set(CMAKE_CXX_COMPILER #{string(cxx)})
          set(CMAKE_OBJC_COMPILER #{string(cc)})
          set(CMAKE_OBJCXX_COMPILER #{string(cxx)})
        CMAKE
      end

      # The toolchain file for the Android ABI +abi+ (<tt>x86_64</tt>),
      # from the NDK at +ndk+, for the API level in the name of the NDK's
      # +compiler+ the runtime was built with
      # (<tt>x86_64-linux-android26-clang</tt>).
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::CMake.android(ndk: "/ndk", abi: "arm64-v8a", compiler: "aarch64-linux-android26-clang")
      #   # => "...set(ANDROID_ABI arm64-v8a)\n..."
      #--
      # SPDX-SnippetEnd
      #++
      def self.android(ndk:, abi:, compiler:)
        api = compiler[/android(\d+)-clang/, 1] or raise Error, "#{compiler} names no Android API level"
        HEADER + <<~CMAKE
          set(ANDROID_ABI #{abi})
          set(ANDROID_PLATFORM android-#{api})
          include(#{string(File.join(ndk, 'build', 'cmake', 'android.toolchain.cmake'))})
        CMAKE
      end

      # +text+ as one quoted argument of CMake's, in which a backslash, a
      # quote, and a dollar sign are escaped (cmake-language(7), "Quoted
      # Argument" and "Escape Sequences").
      def self.string(text)
        "\"#{text.gsub(/[\\"$]/) { |character| "\\#{character}" }}\""
      end
      private_class_method :string
    end
  end
end
