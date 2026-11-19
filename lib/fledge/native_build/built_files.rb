# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../entry"

module Fledge
  class NativeBuild
    # What a gem's build left in its folder that the gem's Ruby may load,
    # and so what ships of it beside the gem's own files.
    #
    # RubyGems leaves a gem's folder as its build left it: an extconf.rb's
    # Makefile installs the extension into the gem's first require path,
    # and RubyGems then runs <tt>make clean</tt>; a Rakefile's build is
    # left whole, wherever it wrote (Gem::Ext::ExtConfBuilder.build and
    # Gem::Ext::RakeBuilder.build, at RubyGems 4.1.0.beta2). So
    # ffi-compiler leaves the library a gem's Ruby gives ffi_lib in
    # <tt>ext/ARCH-OS</tt>, outside every require path. What ships is
    # every file the build wrote into the gem's require paths, and every
    # shared library it wrote anywhere else in the gem's folder, at its
    # path; the rest of what a build leaves (objects, Makefiles, logs, a
    # build tree) no Ruby loads (doc/contributors/design/gems.md, "What a
    # compiled gem ships").
    module BuiltFiles # :nodoc:
      # The names of shared libraries, which ffi_lib, Fiddle.dlopen, and
      # require open by path: Ruby's DLEXT on each platform (+so+,
      # +bundle+, +dll+), and ffi's LIBSUFFIX (+so+, +dylib+, +dll+), with
      # the version numbers a library's file name may carry.
      LIBRARY = /\.(?:so(?:\.\d+)*|bundle|dylib|dll)\z/

      # The debug symbols Apple's linker writes beside a library
      # (<tt>NAME.bundle.dSYM/Contents/Resources/DWARF/NAME.bundle</tt>),
      # which bear its name and are not one.
      DEBUG = %r{\.dSYM/}

      # The entries of what the build wrote into +gem_dir+, the folder it
      # built +package+ in, with paths relative to it: each file in the
      # gem's require paths and each shared library elsewhere that the
      # package does not have, or whose bytes differ from the package's
      # (a path gem's own copy of what the build wrote there, compiled by
      # its developer for their Ruby).
      def self.of(package, gem_dir)
        own = package.contents
        folders = package.spec.require_paths
        found = folders.flat_map { |folder| walk(gem_dir, folder) } + libraries(gem_dir, folders)
        found.uniq(&:path).reject { |entry| entry.type == :directory || own[entry.path] == entry.content.to_s }
      end

      # The entries under +folder+ of +gem_dir+, with paths relative to
      # +gem_dir+.
      private_class_method def self.walk(gem_dir, folder)
        full = File.join(gem_dir, folder)
        return [] unless File.directory?(full)

        Entry.walk(full).map { |entry| entry.with(path: "#{folder}/#{entry.path}") }
      end

      # The shared libraries in +gem_dir+ outside each of +folders+, its
      # require paths, with paths relative to it.
      private_class_method def self.libraries(gem_dir, folders)
        Dir.glob("**/*", File::FNM_DOTMATCH, base: gem_dir).sort.filter_map do |path|
          next unless path.match?(LIBRARY) && !path.match?(DEBUG) && folders.none? { |folder| path.start_with?("#{folder}/") }

          library(File.join(gem_dir, path), path)
        end
      end

      # The Entry of the library at +full+, named +path+, or +nil+ when it
      # is a folder.
      private_class_method def self.library(full, path)
        if File.symlink?(full) then Entry.symlink(path, File.readlink(full))
        elsif File.file?(full) then Entry.file(path, File.binread(full), mode: File.executable?(full) ? 0o755 : 0o644)
        end
      end
    end
  end
end
