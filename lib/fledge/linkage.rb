# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "yaml"
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
  # (Fledge::Binary, with the build computer's tools), and, of those for
  # the app's processor, which alone its process loads, names every
  # library one of them needs that neither the target's operating system,
  # nor Fledge's runtime, nor the gem itself provides.
  # What the operating system provides is SYSTEM_LIBRARIES, and on Linux
  # also what the project lists as its gems' to load from the
  # distribution (Config::Linux), which a desktop library's
  # wrapper needs; on macOS also what the project has the app carry from
  # the developer's computer (Config::Macos), which
  # Fledge::CarriedLibraries copies in and judges. On macOS a
  # library the gem carries must also be where its name leads: a file that
  # names <tt>@rpath/libfoo.dylib</tt> or
  # <tt>@loader_path/libfoo.dylib</tt> loads the gem's copy only if dyld
  # would find it there (Fledge::Linkage::Dyld), so a run path into
  # Homebrew's folder does not count, however the copy is named. It judges
  # nothing else: what a gem compiles in, and under what license, is the
  # app's developer's to decide (decisions of 2026-10-28).
  #
  # Use it for each gem an app ships, through Fledge::AppGems.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    # and Alpine's, and zlib. On Linux, the
    # libraries PEP 600 lets a manylinux_2_39 wheel assume of every
    # distribution with glibc 2.39, Fledge's floor (decision 7):
    # auditwheel 6.4.2's <tt>manylinux-policy.json</tt>,
    # <tt>lib_whitelist</tt> for manylinux_2_39, and glibc's dynamic
    # loader. On Windows, the API sets, which Windows resolves itself, and
    # <tt>combase.dll</tt>, of every Windows from 8 on, as delvewheel
    # 1.13.2, which repairs Python's Windows wheels as auditwheel repairs
    # Linux's, ignores them (<tt>ignore_regexes</tt> in its
    # <tt>delvewheel/_dll_list.py</tt>); each DLL that list's
    # <tt>ignore_names_x64</tt> or <tt>ignore_names_arm64</tt> names is
    # SYSTEM_DLLS. On macOS, anything in <tt>/usr/lib</tt> and the system's
    # frameworks. On Android, the NDK's public libraries for API 26, the
    # oldest the runtime runs on, as the NDK r30 holds their stubs in
    # <tt>sysroot/usr/lib/TRIPLE/26/</tt>, where
    # bionic's <tt>android-changes-for-ndk-developers.md</tt> ("Private
    # API") says the complete list of public libraries is, since from API
    # 24 Android's linker loads an app no other library of the system's;
    # but <tt>libc++.so</tt>, the system's own C++ runtime, which no app
    # may link, where an app carries the NDK's <tt>libc++_shared.so</tt>.
    SYSTEM_LIBRARIES = {
      "linux" => [
        /\A(?:libGL\.so\.1|libICE\.so\.6|libSM\.so\.6|libX11\.so\.6|libXext\.so\.6|libXrender\.so\.1|libanl\.so\.1|libatomic\.so\.1|libc\.so\.6|libdl\.so\.2|libexpat\.so\.1|libgcc_s\.so\.1|libglib-2\.0\.so\.0|libgobject-2\.0\.so\.0|libgthread-2\.0\.so\.0|libm\.so\.6|libnsl\.so\.1|libpthread\.so\.0|libresolv\.so\.2|librt\.so\.1|libstdc\+\+\.so\.6|libutil\.so\.1|libz\.so\.1)\z/,
        /\Ald-linux[-\w.]*\.so\.\d\z/,
      ],
      "linux-musl" => [/\A(?:libc\.so|libc\.musl-(?:x86_64|aarch64)\.so\.1|libz\.so\.1)\z/, /\Ald-musl-(?:x86_64|aarch64)\.so\.1\z/],
      "android" => [
        /\A(?:libEGL|libGLESv1_CM|libGLESv2|libGLESv3|libOpenMAXAL|libOpenSLES|libaaudio|libandroid|libc|libcamera2ndk|libdl|libjnigraphics|liblog|libm|libmediandk|libnativewindow|libstdc\+\+|libsync|libvulkan|libz)\.so\z/,
      ],
      "darwin" => [%r{\A/usr/lib/[^/]+\.dylib\z}, %r{\A/System/Library/Frameworks/}],
      "windows" => [/\Aapi-ms-win-[a-z0-9-]+\.dll\z/i, /\Acombase\.dll\z/i],
      "windows-arm64" => [/\Aapi-ms-win-[a-z0-9-]+\.dll\z/i, /\Acombase\.dll\z/i],
    }.freeze

    # The file that holds SYSTEM_DLLS.
    WINDOWS_DLLS = File.join(File.dirname(__FILE__), "linkage", "windows.yml")

    # By system (Fledge::Platform#libraries), the lowercase names of the
    # DLLs in System32 on every Windows a Fledge app runs on: on x64, every
    # DLL with exports that delvewheel 1.13.2 found there on the
    # installation discs of x64 Windows 7 SP1, 8, 8.1, 10, and 11, and on
    # ARM64, every ARM64 DLL it found there on ARM64 Windows 10 and 11
    # (<tt>ignore_names_x64</tt> and <tt>ignore_names_arm64</tt> in its
    # <tt>delvewheel/_dll_list.py</tt>), which
    # <tt>tasks/windows_dlls.rb</tt> writes into
    # <tt>linkage/windows.yml</tt>. Windows 11 is Fledge's floor, so an
    # older Windows's list assumes less than the floor gives, never more.
    # Microsoft's Visual C++ runtime (<tt>vcruntime140.dll</tt>,
    # <tt>msvcp140.dll</tt>) is in none of them: a computer has it only
    # once something installed the Visual C++ Redistributable.
    SYSTEM_DLLS = YAML.load_file(WINDOWS_DLLS).transform_values { |names| Set.new(names) }.freeze

    # The DLLs of Microsoft's Visual C++ runtime from Visual Studio 2015
    # on, which a DLL built with Visual Studio needs unless it links the
    # runtime statically, and which Windows does not include: those
    # PyInstaller collects as the VC14 runtime (<tt>_win_includes</tt> in
    # its <tt>PyInstaller/depend/dylib.py</tt> at abed52cc, lines 150 to
    # 165).
    VISUAL_C_RUNTIME = /\A(?:concrt140|msvcp140(?:_1|_2|_atomic_wait|_codecvt_ids)?|vccorlib140|vcruntime140(?:_1)?|vcamp140|vcomp140)\.dll\z/i

    # A Windows Ruby's DLL, such as x64-ucrt-ruby410.dll.
    RUBY_DLL = /\A[\w-]*-ruby\d+\.dll\z/i

    # The format each operating system's loader loads.
    FORMATS = {
      "linux" => :elf, "linux-musl" => :elf, "android" => :elf, "darwin" => :macho, "windows" => :pe, "windows-arm64" => :pe
    }.freeze

    # Creates the check.
    #
    # [os] The operating system the app is for (Fledge::Platform#os).
    # [cpu] The processor the app's Ruby runs on (Fledge::Platform#cpu),
    #       whose process loads no code for another: a file whose
    #       Binary#architectures do not include it is not judged, and
    #       provides no library. +nil+ judges every file, as an Android
    #       app's are, each placed in the folder of the ABI it is for,
    #       where Android would load it.
    # [provided] The file names of the shared libraries the runtime
    #            ships, which a compiled file may need too.
    # [system] The file names of the libraries the project lists as its
    #          gems' to load from the Linux distribution
    #          (Config::Linux#system_libraries), which a compiled file
    #          may need too, and #unused names when none does.
    # [readers] The tools that read compiled files here
    #           (Fledge::Binary::Readers).
    # [visual_c_runtime] How the app comes by Microsoft's Visual C++
    #                    runtime (Config::Windows#visual_c_runtime), or
    #                    +nil+ for not at all: with a way chosen, a DLL of
    #                    VISUAL_C_RUNTIME is no gem's problem, and
    #                    #visual_c_libraries names it.
    # [carried] On macOS, the file names of the libraries the project
    #           has the app carry from this computer
    #           (Config::Macos#carried_libraries): a need of one, by any
    #           path, is no gem's problem, since Fledge::CarriedLibraries
    #           copies it in and makes the file load the copy.
    def initialize(os:, cpu: nil, provided: [], system: [], readers: Binary::Readers.local(os), visual_c_runtime: nil, carried: [])
      @system = SYSTEM_LIBRARIES.fetch(os)
      @carried = (os == "darwin") ? carried : []
      @cpu = cpu
      @dlls = SYSTEM_DLLS.fetch(os, Set.new)
      @os = os
      @provided = provided
      @declared = system
      @needed = [] # : Array[String]
      @readers = readers
      @visual_c_runtime = visual_c_runtime
      @visual_c = [] # : Array[String]
    end

    # The DLLs of Microsoft's Visual C++ runtime that the files #problems
    # judged need, by the name the first of them gives each, which the
    # app carries or the computer it goes to has, as the project chose
    # (Config::Windows#visual_c_runtime): empty when it chose neither.
    # Ask after #problems has judged every gem.
    def visual_c_libraries
      @visual_c.uniq(&:downcase)
    end

    # Why the gem whose files are +files+ (paths relative to its folder,
    # and their bytes), named +label+, would not load where the app goes,
    # one sentence each, or none.
    #
    # A file that needs another Ruby's DLL is built for that Ruby, as a
    # gem precompiled for several Ruby versions ships one file for each
    # (<tt>lib/nokogiri/3.4/nokogiri.so</tt>), and the runtime's Ruby
    # never loads it, so it is not judged. Nor is a file for another
    # processor than the app's (+cpu+), as a gem for every platform
    # carries one library for each and loads its own
    # (<tt>lib/libraylib.aarch64.so</tt> beside
    # <tt>lib/libraylib.x86_64.so</tt>).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
      binaries = Binary.parse(loadable, readers: @readers).select { |_, binary| native?(binary) }.sort.to_h
      shipped = (binaries.keys.map { |path| File.basename(path) } + @provided).map(&:downcase)
      dyld = Dyld.new(binaries) if @os == "darwin"
      loaded = binaries.values.filter_map(&:soname)
      binaries.flat_map do |path, binary|
        next [] if binary.needed.any? { |library| library.match?(RUBY_DLL) && !shipped.include?(library.downcase) }

        binary.needed.reject { |library| system?(library) }.filter_map do |library|
          if !shipped.include?(File.basename(library).downcase)
            unprovided(label, path, library) unless loaded_by_name?(library, loaded)
          elsif dyld && !@provided.map(&:downcase).include?(File.basename(library).downcase)
            unreached(label, path, library, dyld, binaries.keys)
          end
        end
      end
    end

    # Why the libraries the project listed as its gems' to load from the
    # Linux distribution (Config::Linux) are wrong, one sentence for each
    # that none of the files #problems judged needed beyond what the
    # system, the runtime, and the gems provide, or none. Ask after
    # #problems has judged every gem.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   linkage = Fledge::Linkage.new(os: "linux", system: ["libgtk-3.so.0"])
    #   linkage.problems("plain 1.0.0", { "lib/plain.rb" => "" }) # => []
    #   linkage.unused.first
    #   # => "fledge.yml's linux: system_libraries lists libgtk-3.so.0, which none of the gems' compiled files needs ..."
    #--
    # SPDX-SnippetEnd
    #++
    def unused
      (@declared - @needed).map do |library|
        "fledge.yml's linux: system_libraries lists #{library}, which none of the gems' compiled files needs beyond what every " \
          "Linux distribution, Fledge's runtime, and the gems themselves provide. Remove it."
      end
    end

    # Whether +library+, which no file of the gem is named, is a name
    # one of the gem's libraries gives itself (+loaded+, each one's
    # Binary#soname), by which the loader gives the need that library
    # once the gem has loaded it by its path: glibc's, on +linux+ (not
    # musl's, whose source was not read for it), for any name equal to a
    # loaded library's SONAME (_dl_map_object in glibc 2.39's
    # <tt>elf/dl-load.c</tt>, lines 1959 to 1985), dyld's for an
    # <tt>@rpath/</tt> name equal to a loaded image's install name, before
    # it searches a run path (Loader::getLoader in dyld-1378's
    # <tt>Loader.cpp</tt>, lines 797 to 808). Whether the gem loads it
    # first is in its Ruby, which this check does not read.
    private def loaded_by_name?(library, loaded)
      return false unless loaded.include?(library)

      @os == "linux" || (@os == "darwin" && library.start_with?("@rpath/"))
    end

    # Whether the app's process could load +binary+ (Binary#for?), or
    # no processor was asked for.
    private def native?(binary)
      cpu = @cpu
      cpu.nil? || binary.for?(cpu)
    end

    # Whether the operating system provides +library+.
    private def system?(library)
      @dlls.include?(library.downcase) || @system.any? { |pattern| pattern.match?(library) }
    end

    # Why the file at +path+ would not load +library+, which nothing
    # provides, or +nil+ when the project listed it as the Linux
    # distribution's (Config::Linux), or as one the macOS app carries
    # (Config::Macos).
    private def unprovided(label, path, library)
      if @declared.include?(library)
        @needed |= [library]
        return
      end
      return if @carried.include?(File.basename(library))

      if @os == "android"
        return "#{label}'s #{path} needs #{library}, which neither Android, nor Fledge's runtime, nor the app's own native libraries " \
          "provide, so the app could not load it on a phone. Build the gem so that it carries the library, or links it statically."
      end

      return visual_c(label, path, library) if library.match?(VISUAL_C_RUNTIME)

      problem = "#{label}'s #{path} needs #{library}, which neither #{@os}, nor Fledge's runtime, nor the gem itself provides, so " \
        "the app could not load it on another computer. Build the gem so that it carries the library, or links it statically"
      case FORMATS.fetch(@os)
      when :elf
        "#{problem}, or, when every computer the app goes to has it from its Linux distribution, list it in fledge.yml as " \
          "linux: { system_libraries: [#{library}] }."
      when :macho
        "#{problem}, or, if you may distribute it, list it in fledge.yml as macos: { carried_libraries: [#{File.basename(library)}] } " \
          "to have the app carry it from this computer."
      else "#{problem}."
      end
    end

    # Why the file at +path+ would not load +library+, a DLL of the Visual
    # C++ runtime, or +nil+ when the project chose how the app comes by
    # it, which #visual_c_libraries then names.
    private def visual_c(label, path, library)
      if @visual_c_runtime
        @visual_c << library
        return
      end

      "#{label}'s #{path} needs #{library}, of Microsoft's Visual C++ runtime, which Windows does not include, so the app could " \
        "not load it on a computer without the Visual C++ Redistributable. Set windows: { visual_c_runtime: local } in fledge.yml " \
        "to copy the runtime from this computer into the app, if you may distribute it (Microsoft limits that to licensed Visual " \
        "Studio users), or windows: { visual_c_runtime: central } if every computer the app goes to has the Redistributable; or " \
        "use a build of the gem that links the runtime statically (/MT)."
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
