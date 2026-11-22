# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../binary"
require_relative "../linkage"
require_relative "android_libraries"

module Fledge
  class MobileProject
    # Whether the native libraries Fledge puts in an Android app would
    # load on a phone.
    #
    # Each library in an app's <tt>lib/ABI/</tt> names the libraries
    # Android's linker must find for it. Android lets an app load only
    # the NDK's public libraries and those the app carries: since API 24
    # its linker refuses every other library of the system's
    # (<tt>android-changes-for-ndk-developers.md</tt> in AOSP's bionic,
    # "Private API"), and nothing of a desktop's Linux is there. A gem's
    # library that names one nothing provides builds without complaint
    # and fails on the phone, with a linker's error that names a gem,
    # when Ruby requires it.
    #
    # This class reads each library Fledge placed in the project with
    # Fledge::Linkage, for Android, and names every library one of them
    # needs that neither Android (Linkage::SYSTEM_LIBRARIES), nor
    # Fledge's runtime (RUNTIME), nor the libraries in the same ABI's
    # folder provide, the host's own among them. It judges each whatever
    # processor it is for: Fledge put it in the folder of the ABI it is
    # for, where Android's linker would load it, so a file for another
    # processor there is not one to let off (Fledge::Linkage, +cpu+).
    #
    # Use it from MobileProject::Android, once the project holds every
    # file.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   linkage = Fledge::MobileProject::AndroidLinkage.new(readers: Fledge::Binary::Readers.llvm(ndk.bin))
    #   linkage.problems(project, [["x86_64", "libfledgeffi.held.libheld.so", "held", "libheld.so"]])
    #   # => ["held's libheld.so needs libxml2.so, which neither Android, nor Fledge's runtime, nor ..."]
    #--
    # SPDX-SnippetEnd
    #++
    class AndroidLinkage
      # The libraries <tt>FledgeRuby.aar</tt> puts beside the app's own
      # in <tt>lib/ABI/</tt> that a library may link: Ruby's.
      RUNTIME = %w[libfledgeruby.so].freeze

      # [readers] The tools that read the libraries
      #           (Fledge::Binary::Readers): the NDK's.
      def initialize(readers:)
        @readers = readers
      end

      # Why the libraries +judged+ names would not load, one sentence
      # each, or none. Each of +judged+ is the ABI, the library's name in
      # +project+'s <tt>src/main/jniLibs/ABI/</tt>, and what a message
      # calls it: whose it is and its path there, as Fledge::Linkage
      # names a gem's file.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   linkage.problems(project, [["x86_64", "libfledgeext.so", "the app", "lib/x86_64/libfledgeext.so"]]) # => []
      #--
      # SPDX-SnippetEnd
      #++
      def problems(project, judged)
        judged.group_by(&:first).flat_map do |abi, files|
          folder = File.join(project, "src", "main", "jniLibs", abi)
          carried = Dir.children(folder).select { |name| name.end_with?(".so") }
          linkage = Linkage.new(os: "android", provided: RUNTIME + carried, readers: @readers)
          files.flat_map { |_, name, label, path| linkage.problems(label, { path => File.binread(File.join(folder, name)) }) }
        end.uniq
      end

      # Why the compiled files a gem keeps in its folder in +root+, the
      # Ruby root that becomes <tt>fledge.zip</tt>, would not load, one
      # sentence each, or none. A gem's Ruby opens such a file by its
      # path, from the copy the app unpacks into its own files, as
      # raylib-bindings opens the library it carries for the processor
      # it runs on, so each is judged as a desktop's build judges a gem's
      # file (Fledge::Linkage), for each ABI the project has, against
      # what Android, the runtime, and that ABI's native libraries
      # provide, and only for that ABI's processor. +gem_folders+ names
      # each gem's folder in +root+ and what a message calls the gem
      # (Fledge::AppGems#gem_folders). A file at a path +root+'s
      # AndroidLibraries::LINKS names is not judged: the runtime puts a
      # native library there, judged by #problems.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   linkage.zipped(project, root, { "lib/ruby/gems/4.1.0+5/gems/drawn-1.0.0" => "drawn 1.0.0" })
      #   # => ["drawn 1.0.0's lib/libdrawn.x86_64.so needs libc.so.6, which neither Android, nor ..."]
      #--
      # SPDX-SnippetEnd
      #++
      def zipped(project, root, gem_folders)
        linked = linked_paths(root)
        gems = gem_folders.filter_map do |folder, label|
          files = compiled_files(root, folder, linked)
          [label, files] unless files.empty?
        end # : Array[[String, Hash[String, String]]]
        return [] if gems.empty?

        MobileExtensions::Targets::ANDROID_ABIS.values.sort.flat_map do |abi|
          folder = File.join(project, "src", "main", "jniLibs", abi)
          carried = File.directory?(folder) ? Dir.children(folder).select { |name| name.end_with?(".so") } : [] # : Array[String]
          linkage = Linkage.new(os: "android", cpu: CPUS.fetch(abi), provided: RUNTIME + carried, readers: @readers)
          gems.flat_map { |label, files| linkage.problems(label, files) }
        end.uniq
      end

      # The processor each ABI's code is for, as Fledge::Binary#for? names
      # it.
      CPUS = { "arm64-v8a" => "aarch64", "x86_64" => "x86_64" }.freeze

      # The paths, relative to +root+, at which its
      # AndroidLibraries::LINKS puts a native library.
      private def linked_paths(root)
        links = File.join(root, AndroidLibraries::LINKS)
        File.file?(links) ? File.foreach(links).filter_map { |line| line.chomp.split("\t")[2] } : []
      end

      # The ELF files in +folder+ of +root+, by their paths in it, with
      # their bytes, but those at a path in +linked+.
      private def compiled_files(root, folder, linked)
        base = File.join(root, folder)
        return {} unless File.directory?(base)

        found = {} # : Hash[String, String]
        Dir.glob("**/*", File::FNM_DOTMATCH, base:).sort.each_with_object(found) do |path, files|
          full = File.join(base, path)
          next if !File.file?(full) || File.symlink?(full) || linked.include?("#{folder}/#{path}")
          next unless Binary.format_of(File.binread(full, 8).to_s) == :elf

          files[path] = File.binread(full)
        end
      end
    end
  end
end
