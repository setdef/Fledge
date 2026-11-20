# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "../command"
require_relative "../error"
require_relative "../mobile_extensions"

module Fledge
  class MobileProject
    # Puts the libraries an Android app's Ruby opens by path into the
    # Gradle project, and says where Ruby looks for each.
    #
    # An Android app's Ruby opens some of its gems' compiled code from
    # files: each extension built as a file
    # (MobileExtensions::Library), and each library a gem's Rakefile
    # built for Ruby's ffi (MobileExtensions::FfiLibrary). The package
    # installer extracts only <tt>lib/ABI/lib*.so</tt> entries, into a
    # folder whose name changes with each install, so no such file can
    # sit where the gem's Ruby asks for it.
    #
    # This class copies each into its ABI's folder of
    # <tt>src/main/jniLibs/</tt>, stripped, with the shared libraries it
    # links, under a name of Fledge's own, adds the NDK's shared C++
    # runtime where one of them names it, and writes
    # <tt>fledge.links</tt> in the Ruby root: a line for each ABI, name,
    # and path where a desktop has the file, which the runtime links to
    # the extracted library as the app starts
    # (<tt>runtime/mobile/library_links.c</tt>).
    #
    # Use it from MobileProject::Android, once the extensions are built.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileProject::AndroidLibraries.new(built).call(project, ruby_root: File.join(project, "fledge"))
    #--
    # SPDX-SnippetEnd
    #++
    class AndroidLibraries
      # The file in the Ruby root that names, for each ABI, a library in
      # <tt>jniLibs/</tt> and each path the app's Ruby looks for it at.
      LINKS = "fledge.links"

      # What begins the name of an extension built as a file:
      # <tt>libfledgeext.FEATURE.so</tt>, beside <tt>libfledgeext.so</tt>,
      # which holds the extensions linked in.
      EXTENSION = "libfledgeext"

      # What begins the name of a library for Ruby's ffi:
      # <tt>libfledgeffi.GEM.PATH.so</tt>.
      FFI = "libfledgeffi"

      # The NDK's shared C++ runtime, which its clang++ links a shared
      # library with unless told <tt>-static-libstdc++</tt>, and which no
      # Android system offers an app: the app carries it.
      CXX_RUNTIME = "libc++_shared.so"

      # The file in the app's <tt>notices/</tt> that says what CXX_RUNTIME
      # is, where it came from, and its license, in an app that carries it.
      CXX_RUNTIME_NOTICE = "libc++_shared.txt"

      # The NDK's notice for the toolchain CXX_RUNTIME belongs to, relative
      # to the toolchain's folder, the parent of NDK#bin.
      CXX_RUNTIME_LICENSE = "NOTICE"

      # What CXX_RUNTIME_NOTICE says before the NDK's notice.
      CXX_RUNTIME_TEXT = <<~TEXT
        The C++ runtime in this app

        %<files>s, among the app's native libraries, is the
        Android NDK's shared C++ runtime, LLVM's libc++ and libc++abi. fledge
        build copied it from the NDK that built the app, %<ndk>s, since a
        library of the app's gems links it. It is the work of the LLVM
        project's authors, under the Apache License v2.0 with LLVM Exceptions.
        The NDK's notice for its toolchain follows, as the NDK ships it, in
        toolchains/llvm/prebuilt/HOST/%<license>s.


      TEXT

      # The characters the package installer takes in a native library's
      # name (<tt>isFilenameSafe</tt>, AOSP's <tt>ApkParsing.cpp</tt>).
      SAFE = /\A[A-Za-z0-9+,\-.=_]+\z/

      # [built] The MobileExtensions::Built whose libraries the app
      #         carries.
      def initialize(built)
        @built = built
      end

      # Copies each library into +project+'s <tt>jniLibs/</tt> and writes
      # LINKS in +ruby_root+, when there is any. Raises Fledge::Error for a
      # library whose name Android cannot install, or two that would have
      # one name.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileProject::AndroidLibraries.new(built).call(project, ruby_root:)
      #   File.read(File.join(ruby_root, "fledge.links"))
      #   # => "x86_64\tlibfledgeext.adder.adder.so\tapp/gems/adder/lib/adder/adder.so\n"
      #--
      # SPDX-SnippetEnd
      #++
      def call(project, ruby_root:)
        carried = [] # : Array[String]
        lines = @built.targets.values.flat_map do |build|
          abi = build.target.abi.to_s
          folder = File.join(project, "src", "main", "jniLibs", abi)
          FileUtils.mkdir_p(folder)
          lines = extensions(build, folder, abi) + ffi_libraries(build, folder, abi)
          carried << abi if carry_cxx_runtime(build, folder)
          lines
        end
        File.write(File.join(ruby_root, LINKS), lines.join) unless lines.empty?
        write_cxx_runtime_notice(ruby_root, carried) unless carried.empty?
      end

      # The LINKS lines of +build+'s extensions built as files, each
      # copied into +folder+ with the shared libraries it links.
      private def extensions(build, folder, abi)
        build.libraries.flat_map do |library|
          name = extension_name(library.feature)
          place(library.path, folder, name)
          MobileExtensions::Linking.carry_shared_libraries(library.flags, into: folder)
          library.links.map { |link| "#{abi}\t#{name}\t#{link}\n" }
        end
      end

      # The LINKS lines of +build+'s libraries for Ruby's ffi, each copied
      # into +folder+ under a name made from its gem and its path in the
      # gem, which no two libraries of one app share.
      private def ffi_libraries(build, folder, abi)
        named = {} # : Hash[String, MobileExtensions::FfiLibrary]
        build.ffi_libraries.flat_map do |library|
          name = ffi_name(library)
          if (other = named[name])
            raise Error, "#{other.gem}'s #{other.file} and #{library.gem}'s #{library.file} would both be #{name} in the " \
              "Android app's #{abi} libraries"
          end

          named[name] = library
          place(library.path, folder, name)
          library.links.map { |link| "#{abi}\t#{name}\t#{link}\n" }
        end
      end

      # The name in <tt>jniLibs/</tt> of the extension +feature+:
      # EXTENSION, then the feature with its slashes as dots. Raises
      # Fledge::Error for a feature with characters outside SAFE.
      private def extension_name(feature)
        name = "#{EXTENSION}.#{feature.tr('/', '.')}.so"
        return name if name.match?(SAFE)

        raise Error, "the extension #{feature} has a name Android cannot install as a native library: only letters, digits, and + , - . = _"
      end

      # The name in <tt>jniLibs/</tt> of +library+: FFI, then its gem's
      # name and its path in the gem with the slashes as dots, ending in
      # <tt>.so</tt>, which the installer extracts. Raises Fledge::Error
      # for one with characters outside SAFE.
      private def ffi_name(library)
        name = "#{FFI}.#{library.gem}.#{library.file.tr('/', '.')}"
        name = "#{name}.so" unless name.end_with?(".so")
        return name if name.match?(SAFE)

        raise Error, "#{library.gem}'s library for ffi #{library.file} has a path Android cannot install as a native library: " \
          "only letters, digits, and + , - . = _"
      end

      # Copies the NDK's shared C++ runtime for +build+'s ABI into
      # +folder+ when a library there names it, as one a gem's own build
      # linked with the NDK's clang++ does (CXX_RUNTIME), so that Android
      # finds it among the app's native libraries, as the Android Gradle
      # plugin packs it for a CMake build that asks for
      # <tt>c++_shared</tt>.
      # Returns whether it copied it.
      private def carry_cxx_runtime(build, folder)
        ndk = @built.ndk or return false
        readelf = File.join(ndk.bin, "llvm-readelf")
        needed = Dir.glob(File.join(folder, "*.so")).any? do |library|
          Command.run(readelf, "--needed-libs", library, install: "Install the Android NDK again: #{ndk.root} has no llvm-readelf.")
            .split.include?(CXX_RUNTIME)
        end
        FileUtils.cp(File.join(ndk.bin, "..", "sysroot", "usr", "lib", build.target.name, CXX_RUNTIME), folder) if needed
        needed
      end

      # Writes CXX_RUNTIME_NOTICE in the app's <tt>notices/</tt> under
      # +ruby_root+, for the C++ runtime carried for +abis+: which files it
      # covers, where they came from, and the NDK's own notice for the
      # toolchain they belong to (CXX_RUNTIME_LICENSE). The runtime's
      # NOTICES.txt cannot hold it: the runtime holds no such library.
      private def write_cxx_runtime_notice(ruby_root, abis)
        ndk = @built.ndk or return
        license = File.join(ndk.bin, "..", CXX_RUNTIME_LICENSE)
        raise Error, "Install the Android NDK again: #{ndk.root} has no #{CXX_RUNTIME_LICENSE}." unless File.file?(license)

        folder = File.join(ruby_root, "notices")
        FileUtils.mkdir_p(folder)
        files = abis.map { |abi| "lib/#{abi}/#{CXX_RUNTIME}" }.join(" and ")
        File.write(File.join(folder, CXX_RUNTIME_NOTICE), format(CXX_RUNTIME_TEXT, files:, ndk: File.basename(ndk.root),
          license: CXX_RUNTIME_LICENSE) + File.read(license))
      end

      # Copies +path+ into +folder+ as +name+, stripped with the NDK's
      # llvm-strip where the build had the NDK.
      private def place(path, folder, name)
        into = File.join(folder, name)
        FileUtils.cp(path, into)
        ndk = @built.ndk or return

        Command.run(File.join(ndk.bin, "llvm-strip"), "--strip-unneeded", into, install: "Install the Android NDK again: #{ndk.root} has no llvm-strip.")
      end
    end
  end
end
