# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require_relative "../error"

module Fledge
  class MobileExtensions
    # Reads what system a shared library was built for, with the phone's
    # own tools: Xcode's <tt>vtool -show-build</tt>, which prints the
    # platform each Mach-O file's <tt>LC_BUILD_VERSION</tt> names, and the
    # NDK's <tt>llvm-readelf</tt>, which prints an ELF file's machine and
    # its notes, among them the <tt>Android</tt> note the NDK's
    # <tt>crtbegin_so.o</tt> puts in every library it links.
    #
    # Ruby's ffi takes iOS for <tt>darwin</tt> and Android for
    # <tt>linux</tt> (<tt>lib/ffi/platform.rb</tt> at 1.17.4), so a gem
    # whose package holds a library for macOS or for a desktop's Linux
    # asks <tt>dlopen</tt> for it on a phone (#desktop?).
    #
    # Use it from Fledge::MobileExtensions::RakeBuild, for each shared
    # library a Rakefile's build leaves.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   built_for = Fledge::MobileExtensions::BuiltFor.new(ndk: nil)
    #   built_for.call(target, "ext/aarch64-darwin/libllhttp-ext.bundle") # => "macOS"
    #   built_for.wanted(target)                                          # => "the iOS Simulator"
    #--
    # SPDX-SnippetEnd
    #++
    class BuiltFor
      # How a message names each platform <tt>vtool</tt> prints.
      APPLE = { "IOS" => "iOS", "IOSSIMULATOR" => "the iOS Simulator", "MACOS" => "macOS", "MACCATALYST" => "Mac Catalyst" }.freeze

      # The ABI of each machine <tt>llvm-readelf -h</tt> prints.
      MACHINES = { "AArch64" => "arm64-v8a", "Advanced Micro Devices X86-64" => "x86_64" }.freeze

      # Creates the reader, for Android with +ndk+'s tools, or for iOS
      # with Xcode's when +ndk+ is +nil+.
      def initialize(ndk:)
        @ndk = ndk
      end

      # What the shared library at +path+ was built for, as #wanted names
      # +target+'s: <tt>"iOS"</tt>, <tt>"macOS"</tt>, <tt>"Android
      # x86_64"</tt>, <tt>"Linux x86_64"</tt>, or what it is not, when
      # it is no file of the target's kind.
      def call(target, path)
        target.abi ? elf(path) : apple(path)
      end

      # What +target+'s libraries are built for.
      def wanted(target)
        target.abi ? "Android #{target.abi}" : APPLE.fetch(target.name.end_with?("-simulator") ? "IOSSIMULATOR" : "IOS")
      end

      # Whether +system+, what #call said a library is built for, is the
      # desktop that the phone of +target+ is to Ruby's ffi: macOS for
      # iOS, a desktop's Linux for Android.
      def desktop?(target, system)
        target.abi ? system.start_with?("Linux ") : system == "macOS"
      end

      # The platforms <tt>vtool</tt> reads in the Mach-O file at +path+.
      private def apple(path)
        output, status = capture("xcrun", "vtool", "-show-build", path, install: INSTALL_XCODE)
        platforms = output.scan(/^\s*platform (\S+)/).flatten.uniq
        return "no Apple system" if !status.success? || platforms.empty?

        platforms.map { |platform| APPLE.fetch(platform, platform) }.join(" and ")
      end

      # The system and ABI <tt>llvm-readelf</tt> reads in the ELF file at
      # +path+.
      private def elf(path)
        ndk = @ndk or raise Error, "reading an Android library needs the NDK"
        output, status = capture(File.join(ndk.bin, "llvm-readelf"), "-h", "-n", path,
          install: "Install the Android NDK again: #{ndk.root} has no llvm-readelf.")
        machine = output[/^\s*Machine:\s+(.+?)\s*$/, 1]
        return "no Android system" if !status.success? || machine.nil?

        "#{output.match?(/^\s*Android\s+0x/) ? 'Android' : 'Linux'} #{MACHINES.fetch(machine, machine)}"
      end

      # Runs +command+, and returns its output and status; raises
      # Fledge::Error, saying to +install+ it, when it cannot run.
      private def capture(*command, install:)
        Open3.capture2e(*command)
      rescue SystemCallError => e
        raise Error, "fledge build needs #{File.basename(command.first.to_s)}, which it could not run (#{e.message}). #{install}"
      end
    end
  end
end
