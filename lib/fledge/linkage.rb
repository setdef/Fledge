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
  # This class reads each compiled file of a gem in the format of the
  # target's own loader, ELF, Mach-O, or PE, since a loader loads no other
  # (Fledge::Binary, with the build computer's tools), and names every
  # library one of them needs that neither the target's operating system,
  # nor Fledge's runtime, nor the gem itself provides.
  # What the operating system provides is SYSTEM_LIBRARIES. On macOS a
  # library the gem carries must also be where its name leads: a file that
  # names <tt>@rpath/libfoo.dylib</tt> or
  # <tt>@loader_path/libfoo.dylib</tt> loads the gem's copy only if dyld
  # would find it there (Fledge::Linkage::Dyld), so a run path into
  # Homebrew's folder does not count, however the copy is named. It judges
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
    # By system (Fledge::Platform#libraries), the patterns of the
    # libraries it provides, which an app need not ship. On musl Linux,
    # those PEP 656 lets a musllinux_1_2 wheel assume, auditwheel 6.8.2's
    # <tt>musllinux-policy.json</tt>: musl's C library, by its own name
    # and Alpine's, and zlib (ADR 017). On Linux, the
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
      "linux-musl" => [/\A(?:libc\.so|libc\.musl-(?:x86_64|aarch64)\.so\.1|libz\.so\.1)\z/, /\Ald-musl-(?:x86_64|aarch64)\.so\.1\z/],
      "darwin" => [%r{\A/usr/lib/[^/]+\.dylib\z}, %r{\A/System/Library/Frameworks/}],
      "windows" => [
        /\Aapi-ms-win-[a-z0-9-]+\.dll\z/i,
        /\A(?:advapi32|bcrypt|bcryptprimitives|comdlg32|crypt32|dbghelp|gdi32|imagehlp|iphlpapi|kernel32|ncrypt|ntdll|ole32|oleaut32|rpcrt4|secur32|shell32|shlwapi|user32|userenv|uxtheme|version|winmm|ws2_32|wsock32)\.dll\z/i,
      ],
    }.freeze

    # A Windows Ruby's DLL, such as x64-ucrt-ruby400.dll.
    RUBY_DLL = /\A[\w-]*-ruby\d+\.dll\z/i

    # The format each operating system's loader loads.
    FORMATS = { "linux" => :elf, "linux-musl" => :elf, "darwin" => :macho, "windows" => :pe }.freeze

    # Creates the check.
    #
    # [os] The operating system the app is for (Fledge::Platform#os).
    # [provided] The file names of the shared libraries the runtime
    #            ships, which a compiled file may need too.
    # [readers] The tools that read compiled files here
    #           (Fledge::Binary::Readers).
    def initialize(os:, provided: [], readers: Binary::Readers.local(os))
      @system = SYSTEM_LIBRARIES.fetch(os)
      @os = os
      @provided = provided
      @readers = readers
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
      loadable = files.select { |_, content| Binary.format_of(content.byteslice(0, 8).to_s) == FORMATS.fetch(@os) }
      binaries = Binary.parse(loadable, readers: @readers).sort.to_h
      shipped = (binaries.keys.map { |path| File.basename(path) } + @provided).map(&:downcase)
      dyld = Dyld.new(binaries) if @os == "darwin"
      binaries.flat_map do |path, binary|
        next [] if binary.needed.any? { |library| library.match?(RUBY_DLL) && !shipped.include?(library.downcase) }

        binary.needed.reject { |library| @system.any? { |pattern| pattern.match?(library) } }.filter_map do |library|
          if !shipped.include?(File.basename(library).downcase)
            "#{label}'s #{path} needs #{library}, which neither #{@os}, nor Fledge's runtime, nor the gem itself provides, so " \
              "the app could not load it on another computer. Build the gem so that it carries the library, or links it statically."
          elsif dyld && !@provided.map(&:downcase).include?(File.basename(library).downcase)
            unreached(label, path, library, dyld, binaries.keys)
          end
        end
      end
    end

    # Why dyld would not find +library+, which the file at +path+ names
    # and the gem carries among +paths+, or +nil+ when it would, or when
    # where it looks depends on where the gem sits in the app
    # (Fledge::Linkage::Dyld).
    private def unreached(label, path, library, dyld, paths)
      return unless Dyld.relative?(library) && dyld.resolve(path, library).nil?

      copies = paths.select { |copy| File.basename(copy).casecmp?(File.basename(library)) }
      if library.start_with?("@rpath/")
        searched = dyld.run_paths(path)
        folder = copies.first.to_s.delete_suffix("/#{library.delete_prefix('@rpath/')}")
        "#{label}'s #{path} needs #{library}, which the gem carries at #{copies.join(', ')}, but none of the run paths dyld would " \
          "search for it (#{searched.empty? ? 'it has none' : searched.join(', ')}) leads there, so the app could not load it on " \
          "another computer. Give the file a run path that does, such as #{loader_path(path, folder)} (install_name_tool -add_rpath), " \
          "or build the gem so that it has one."
      else
        "#{label}'s #{path} needs #{library}, which is not there: the gem carries #{File.basename(library)} at #{copies.join(', ')}, " \
          "so the app could not load it on another computer. Build the gem so that the file names the library where it is, such as " \
          "#{loader_path(path, copies.first.to_s)}."
      end
    end

    # +target+, a path in the gem's folder, as the file at +path+ reaches
    # it from <tt>@loader_path</tt>.
    private def loader_path(path, target)
      relative = Pathname(target).relative_path_from(Pathname(File.dirname(path))).to_s
      (relative == ".") ? "@loader_path" : "@loader_path/#{relative}"
    end
  end
end

require_relative "linkage/dyld"
