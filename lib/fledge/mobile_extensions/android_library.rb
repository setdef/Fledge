# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "../error"

module Fledge
  class MobileExtensions
    # Links the shared library an Android app loads with its gems'
    # extensions in it, with the NDK's clang, for one ABI.
    #
    # Use it through Fledge::MobileExtensions#shared_library.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileExtensions::AndroidLibrary.new(runner:).call(built, build, registration: "ext.c", into: "jniLibs/x86_64/libfledgeext.so")
    #   # => "jniLibs/x86_64/libfledgeext.so"
    #--
    # SPDX-SnippetEnd
    #++
    class AndroidLibrary
      # Creates the linker, which runs its tools with +runner+ (Runner).
      def initialize(runner:)
        @runner = runner
      end

      # Links the library +into+, for the target of +build+: the
      # registration unit's C file +registration+ and the extensions'
      # archives, against the runtime's <tt>libfledgeruby.so</tt>, aligned
      # for 16 KB pages as the runtime's own library is, with the NDK's C++
      # runtime linked statically (a shared one would be a library the
      # package does not carry) when an extension has C++, and with its
      # run path <tt>$ORIGIN</tt>, so that the runtime's ruby program,
      # which loads it outside the app's own library namespace, finds the
      # shared libraries it needs beside it (ADR 082). Returns +into+.
      def call(built, build, registration:, into:)
        ndk = built.ndk or raise Error, "only an Android app links a shared library"
        target = build.target
        cc = target.environment.fetch("FLEDGE_CC")
        cc = "#{cc}++" if build.cxx
        stl = build.cxx ? ["-static-libstdc++"] : [] # : Array[String]
        FileUtils.mkdir_p(File.dirname(into))
        env = @runner.clean_env
        @runner.call(env, cc, "-shared", "-fPIC", "-O2", "-I", File.join(target.root, "include"), "-o", into, *stl, "-x", "c", registration, "-x", "none",
          *build.archives, "-L#{target.libdir}", "-lfledgeruby", *build.flags, "-llog", "-lm", "-Wl,-z,max-page-size=16384",
          "-Wl,--exclude-libs,ALL", "-Wl,-rpath,$ORIGIN", what: "linking the app's extensions for #{target.name} with #{File.basename(ndk.root)}")
        @runner.call(env, File.join(ndk.bin, "llvm-strip"), "--strip-unneeded", into, what: "stripping #{File.basename(into)} for #{target.name}")
        into
      end
    end
  end
end
