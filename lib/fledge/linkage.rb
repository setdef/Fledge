# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "binary"

module Fledge
  # Whether a gem's compiled files would load on the computer an app goes
  # to.
  #
  # A compiled file names the shared libraries the system's loader must
  # find for it. A gem built on a developer's computer can name one only
  # that computer has (nokogiri's vendored libxml2, built from source on a
  # Mac with Homebrew, linked Homebrew's liblzma), and the app would then
  # fail to start everywhere else, with a loader's error that names a gem,
  # which a person who runs the app must never meet (AGENTS.md, Design
  # precedence 1).
  #
  # This class reads each compiled file of a gem (Fledge::Binary) and
  # names every library one of them needs that neither the target's
  # operating system, nor Fledge's runtime, nor the gem itself provides.
  # What the operating system provides is SYSTEM_LIBRARIES. It judges
  # nothing else: what a gem compiles in, and under what license, is the
  # app's developer's to decide (decisions of 2026-10-28; ADR 007).
  #
  # Use it for each gem an app ships, through Fledge::AppGems.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   package = Fledge::GemPackage.new("sqlite3-2.10.2-x86_64-linux-gnu.gem")
  #   Fledge::Linkage.new(os: "linux").problems("sqlite3 2.10.2", package.contents) # => []
  #--
  # SPDX-SnippetEnd
  #++
  class Linkage
    # By operating system (Fledge::Platform#os), the patterns of the
    # libraries it provides, which an app need not ship. On Linux, the
    # libraries PEP 600 lets a manylinux_2_39 wheel assume of every
    # distribution with glibc 2.39, Fledge's floor (decision 7):
    # auditwheel 6.4.2's <tt>manylinux-policy.json</tt>,
    # <tt>lib_whitelist</tt> for manylinux_2_39, and glibc's dynamic
    # loader. Elsewhere, <tt>runtime/licenses.yml</tt>'s
    # <tt>system_libraries</tt>, which a runtime's own files meet, and on
    # Windows <tt>bcryptprimitives.dll</tt> too, whose ProcessPrng the Rust
    # standard library imports for random numbers (its
    # x86_64-pc-windows-gnu libstd rlib names both, at Rust 1.99.1).
    SYSTEM_LIBRARIES = {
      "linux" => [
        /\A(?:libGL\.so\.1|libICE\.so\.6|libSM\.so\.6|libX11\.so\.6|libXext\.so\.6|libXrender\.so\.1|libanl\.so\.1|libatomic\.so\.1|libc\.so\.6|libdl\.so\.2|libexpat\.so\.1|libgcc_s\.so\.1|libglib-2\.0\.so\.0|libgobject-2\.0\.so\.0|libgthread-2\.0\.so\.0|libm\.so\.6|libnsl\.so\.1|libpthread\.so\.0|libresolv\.so\.2|librt\.so\.1|libstdc\+\+\.so\.6|libutil\.so\.1|libz\.so\.1)\z/,
        /\Ald-linux[-\w.]*\.so\.\d\z/,
      ],
      "darwin" => [%r{\A/usr/lib/[^/]+\.dylib\z}, %r{\A/System/Library/Frameworks/}],
      "windows" => [
        /\Aapi-ms-win-[a-z0-9-]+\.dll\z/i,
        /\A(?:advapi32|bcrypt|bcryptprimitives|comdlg32|crypt32|dbghelp|gdi32|imagehlp|iphlpapi|kernel32|ncrypt|ntdll|ole32|oleaut32|rpcrt4|secur32|shell32|shlwapi|user32|userenv|uxtheme|version|winmm|ws2_32|wsock32)\.dll\z/i,
      ],
    }.freeze

    # A Windows Ruby's DLL, such as x64-ucrt-ruby400.dll.
    RUBY_DLL = /\A[\w-]*-ruby\d+\.dll\z/i

    # Creates the check.
    #
    # [os] The operating system the app is for (Fledge::Platform#os).
    # [provided] The file names of the shared libraries the runtime
    #            ships, which a compiled file may need too.
    def initialize(os:, provided: [])
      @system = SYSTEM_LIBRARIES.fetch(os)
      @os = os
      @provided = provided
    end

    # Why the gem whose files are +files+ (paths relative to its folder,
    # and their bytes), named +label+, would not load where the app goes,
    # one sentence each, or none.
    #
    # A file that needs another Ruby's DLL is built for that Ruby, as a
    # gem precompiled for several Ruby versions ships one file for each
    # (<tt>lib/nokogiri/3.4/nokogiri.so</tt>), and the runtime's Ruby
    # never loads it, so it is not judged.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   linkage = Fledge::Linkage.new(os: "linux", provided: ["libcrypt.so.2"])
    #   linkage.problems("mystery 1.0.0", { "lib/mystery.so" => File.binread("mystery.so") }).first
    #   # => "mystery 1.0.0's lib/mystery.so needs libxml2.so.2, which neither linux, nor Fledge's runtime, nor ..."
    #--
    # SPDX-SnippetEnd
    #++
    def problems(label, files)
      binaries = files.filter_map { |path, content| Binary.parse(content)&.then { |found| [path, found] } }.sort.to_h
      shipped = (binaries.keys.map { |path| File.basename(path) } + @provided).map(&:downcase)
      binaries.flat_map do |path, binary|
        next [] if binary.needed.any? { |library| library.match?(RUBY_DLL) && !shipped.include?(library.downcase) }

        binary.needed.reject { |library| @system.any? { |pattern| pattern.match?(library) } || shipped.include?(File.basename(library).downcase) }
          .map do |library|
            "#{label}'s #{path} needs #{library}, which neither #{@os}, nor Fledge's runtime, nor the gem itself provides, so " \
              "the app could not load it on another computer. Build the gem so that it carries the library, or links it statically."
          end
      end
    end
  end
end
