# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "shellwords"

module Fledge
  class MobileExtensions
    # What each target of a phone links of its extensions (ADR 022 and
    # ADR 025).
    #
    # An extconf.rb names what its extension links in mkmf's
    # <tt>$libs</tt> and <tt>$LOCAL_LIBS</tt>: system libraries,
    # frameworks, and libraries of its own or another's, such as SDL3,
    # built for that one target. A phone's project links them in
    # different places: an iOS slice's static libraries with that slice's
    # extensions, the flags every slice shares in the Xcode project, and
    # an Android ABI's shared libraries in the APK beside
    # <tt>libfledgeext.so</tt>.
    #
    # This module sorts them. Use it to read an extconf.rb's flags, to
    # gather a target's archives and flags into a TargetBuild, and to
    # carry the shared libraries an Android extension links.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   flags = Fledge::MobileExtensions::Linking.link_flags("-L/sdl/lib -lSDL3 -framework UIKit", dir: "/work")
    #   Fledge::MobileExtensions::Linking.shared_libraries(flags) # => ["/sdl/lib/libSDL3.so"]
    #--
    # SPDX-SnippetEnd
    #++
    module Linking
      # The names of the C++ runtime a desktop's link takes, which an
      # extconf.rb gives when its extension is C and a library it links is
      # C++: a Mac's and Linux's (ADR 027).
      CXX_RUNTIMES = %w[-lc++ -lstdc++].freeze

      # The linker flags in +text+, the <tt>$libs</tt> and
      # <tt>$LOCAL_LIBS</tt> an extconf.rb gave mkmf, that an app's link
      # needs: libraries (<tt>-l</tt>), their folders (<tt>-L</tt>), frameworks,
      # and static libraries, the gem's own or another's (SDL3's libSDL3.a),
      # whose relative paths are made absolute from +dir+, the folder it
      # built them in. Compiler flags and the like are the extension's own,
      # already compiled in. Each appears once. A framework is one flag,
      # <tt>-Wl,-framework,NAME</tt>, the form SDL3's sdl3.pc writes and
      # clang passes to the linker, so that merging flags never parts a
      # framework from its name. The C++ runtime (CXX_RUNTIMES) is left
      # out: each phone links its own (.cxx_runtime?).
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Linking.link_flags("-lz -framework Security ./libx.a -O2", dir: "/work")
      #   # => ["-lz", "-Wl,-framework,Security", "/work/libx.a"]
      #--
      # SPDX-SnippetEnd
      #++
      def self.link_flags(text, dir:)
        tokens = text.shellsplit
        flags = [] # : Array[String]
        until tokens.empty?
          token = tokens.shift.to_s
          case token
          when *CXX_RUNTIMES then next
          when "-framework", "-weak_framework" then flags << "-Wl,#{token},#{tokens.shift}"
          when /\A-Wl,-(?:weak_)?framework,[^,]+\z/, /\A-l./ then flags << token
          when /\A-L(.+)/ then flags << "-L#{File.expand_path(::Regexp.last_match(1).to_s, dir)}"
          when /\.a\z/ then flags << File.expand_path(token, dir)
          end
        end
        flags.uniq
      end

      # Whether +text+, the <tt>$libs</tt> and <tt>$LOCAL_LIBS</tt> an
      # extconf.rb gave mkmf, names the C++ runtime (CXX_RUNTIMES), as a C
      # extension over a C++ library does. Such an extension links as one
      # with C++ sources does: with <tt>-lc++</tt> on iOS, and on Android
      # with the NDK's C++ runtime linked in statically, since the
      # <tt>libc++_shared.so</tt> that <tt>-lc++</tt> names there is a
      # library the package does not carry.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Linking.cxx_runtime?("/work/libtally.a -lstdc++") # => true
      #--
      # SPDX-SnippetEnd
      #++
      def self.cxx_runtime?(text)
        text.shellsplit.intersect?(CXX_RUNTIMES)
      end

      # What +target+ links of its extensions' +reports+, a TargetBuild: each
      # extension's archive and then the static libraries its extconf.rb
      # named, which are that target's alone (an iOS slice's libSDL3.a), as
      # its archives; and the rest of the flags, which every target may
      # share, once each.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   build = Fledge::MobileExtensions::Linking.target_build(target, reports)
      #   build.archives # => ["/work/x/x.a", "/sdl/ios-arm64/lib/libSDL3.a"]
      #   build.flags # => ["-Wl,-framework,UIKit", "-lm"]
      #--
      # SPDX-SnippetEnd
      #++
      def self.target_build(target, reports)
        archives = [] # : Array[String]
        flags = [] # : Array[String]
        reports.each do |report|
          libraries, rest = report.flags.partition { |flag| flag.end_with?(".a") }
          archives.push(report.archive, *libraries)
          flags.concat(rest)
        end
        TargetBuild.new(target:, archives: archives.uniq, flags: flags.uniq, cxx: reports.any?(&:cxx))
      end

      # The shared libraries +flags+ link from the folders they name, each
      # <tt>-lNAME</tt> found as <tt>libNAME.so</tt> in a <tt>-L</tt> folder,
      # such as SDL3's <tt>libSDL3.so</tt>. An Android app loads native
      # code only from the libraries its package holds, so these go into
      # it beside <tt>libfledgeext.so</tt>; a name found in no such folder
      # is the system's, as <tt>-llog</tt> is.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Linking.shared_libraries(["-L/sdl/x86_64/lib", "-lSDL3", "-llog"])
      #   # => ["/sdl/x86_64/lib/libSDL3.so"]
      #--
      # SPDX-SnippetEnd
      #++
      def self.shared_libraries(flags)
        folders = flags.filter_map { |flag| flag.delete_prefix("-L") if flag.start_with?("-L") }
        flags.filter_map do |flag|
          next unless flag.start_with?("-l")

          folders.map { |folder| File.join(folder, "lib#{flag.delete_prefix('-l')}.so") }.find { |path| File.file?(path) }
        end.uniq
      end

      # Copies the shared libraries +flags+ link (Linking.shared_libraries)
      # into the folder +into+, an ABI's <tt>jniLibs</tt>, where the
      # Android Gradle plugin packs them as it packs
      # <tt>libfledgeext.so</tt>, and returns their copies' paths.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileExtensions::Linking.carry_shared_libraries(["-L/sdl/x86_64/lib", "-lSDL3"], into: "src/main/jniLibs/x86_64")
      #   # => ["src/main/jniLibs/x86_64/libSDL3.so"]
      #--
      # SPDX-SnippetEnd
      #++
      def self.carry_shared_libraries(flags, into:)
        shared_libraries(flags).map do |library|
          copy = File.join(into, File.basename(library))
          FileUtils.cp(library, copy)
          copy
        end
      end
    end
  end
end
