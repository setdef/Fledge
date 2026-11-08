# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"

module Fledge
  class MobileExtensions
    # The Android NDK on this computer, whose clang compiles an app's
    # extensions for Android (ADR 022): the one the developer installed
    # for Android Studio or Gradle, found where Gradle's Android plugin and
    # Google's tools look for it, since Fledge downloads no toolchain onto
    # a developer's computer. Its tools are the very ones Fledge's runtime
    # was built with, from the NDK Google publishes (<tt>runtime/sources.yml</tt>
    # pins its r30), and any NDK of r26 or later has the same names.
    #
    # Use NDK.find, with the environment.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   ndk = Fledge::MobileExtensions::NDK.find(ENV, host: Fledge::Platform.local)
    #   ndk.bin # => "/Users/you/Library/Android/sdk/ndk/30.0.16248370/toolchains/llvm/prebuilt/darwin-x86_64/bin"
    #--
    # SPDX-SnippetEnd
    #++
    class NDK
      # The name of NDK's prebuilt toolchain folder for each computer
      # that builds an Android project with extensions: the NDK's Mac
      # toolchain is one program for Intel and Apple silicon alike.
      TAGS = { "arm64-darwin" => "darwin-x86_64", "x86_64-linux" => "linux-x86_64" }.freeze

      # The variables that name an NDK, in the order Google's tools prefer
      # them (<tt>ANDROID_NDK_HOME</tt> is the older and deprecated).
      VARIABLES = %w[ANDROID_NDK_ROOT ANDROID_NDK_HOME].freeze

      # The NDK version <tt>sdkmanager</tt> installs that Fledge's
      # runtime is built with, for the message when none is found.
      RECOMMENDED = "30.0.16248370"

      # The NDK's folder.
      attr_reader :root

      # The NDK in +env+'s ANDROID_NDK_ROOT or ANDROID_NDK_HOME, or else
      # the newest under <tt>ndk/</tt> in the Android SDK that
      # ANDROID_HOME, ANDROID_SDK_ROOT, or the SDK Manager's default
      # folder names. Raises Fledge::Error naming where it looked and how
      # to install one when there is none, or when a variable names a
      # folder that has no toolchain for +host+.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::NDK.find({ "ANDROID_NDK_ROOT" => "/opt/ndk" }, host: host).root # => "/opt/ndk"
      #--
      # SPDX-SnippetEnd
      #++
      def self.find(env, host:)
        VARIABLES.each do |name|
          folder = env[name].to_s
          next if folder.empty?

          ndk = new(folder, host:)
          return ndk if ndk.usable?

          raise Error, "#{name} names #{folder}, which has no NDK toolchain for #{host}: #{ndk.bin} is missing."
        end
        looked = sdks(env)
        candidates = looked.flat_map { |sdk| Dir.glob(File.join(sdk, "ndk", "*")) }.select { |folder| new(folder, host:).usable? }
        newest = candidates.max_by { |folder| Gem::Version.new(File.basename(folder)[/\A[\d.]+/] || "0") }
        return new(newest, host:) if newest

        raise Error, "fledge build needs the Android NDK to compile a gem's extension for Android, and found none. Install it " \
          "with Android Studio's SDK Manager or sdkmanager \"ndk;#{RECOMMENDED}\", and set ANDROID_NDK_ROOT to its folder " \
          "if it is not in an SDK that ANDROID_HOME names. It looked in #{VARIABLES.join(', ')} and in " \
          "#{looked.map { |sdk| File.join(sdk, 'ndk') }.join(', ')}."
      end

      # The Android SDKs +env+ names or the SDK Manager makes by default.
      def self.sdks(env)
        home = env["HOME"] || Dir.home
        [env["ANDROID_HOME"], env["ANDROID_SDK_ROOT"], File.join(home, "Library", "Android", "sdk"), File.join(home, "Android", "Sdk")]
          .map(&:to_s).reject(&:empty?).uniq
      end
      private_class_method :sdks

      # Creates the NDK at +root+ for +host+, the Fledge::Platform of this
      # computer.
      def initialize(root, host:)
        @root = root
        @host = host
      end

      # The folder of the NDK's compilers and binutils for this computer.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   ndk.bin # => "/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
      #--
      # SPDX-SnippetEnd
      #++
      def bin
        File.join(@root, "toolchains", "llvm", "prebuilt", TAGS.fetch(@host.name, @host.name), "bin")
      end

      # Whether the NDK has a toolchain for this computer.
      def usable?
        File.directory?(bin)
      end
    end
  end
end
