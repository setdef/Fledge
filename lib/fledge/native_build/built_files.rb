# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../entry"

module Fledge
  class NativeBuild
    # What a gem's build left in its folder, which ships beside the gem's
    # own files, and what of it Ruby may load, which the checks read.
    #
    # RubyGems leaves a gem's folder as its build left it: an extconf.rb's
    # Makefile installs the extension into the gem's first require path,
    # and RubyGems then runs <tt>make clean</tt>; a Rakefile's build is
    # left whole, wherever it wrote; only the build's logs are removed
    # (Gem::Ext::ExtConfBuilder.build, Gem::Ext::RakeBuilder.build, and
    # Gem::Ext::Builder#build_extension, at RubyGems 4.1.0.beta2). So
    # under <tt>bundle exec</tt> a gem's Ruby may read, by its path, any
    # file its build left: the library ffi-compiler leaves for ffi_lib in
    # <tt>ext/ARCH-OS</tt>, or data an extconf.rb generates. Every such
    # file ships at its path; the linkage and floors checks read those in
    # the gem's require paths and the shared libraries, which Ruby, ffi,
    # and fiddle open.
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
      # built +package+ in, with paths relative to it: each file the
      # package does not have, or whose bytes differ from the package's
      # (a path gem's own copy of what the build wrote there, compiled by
      # its developer for their Ruby). Neither git's files, such as a
      # submodule's <tt>.git</tt> in a git gem's copy, which a git or path
      # gem ships without, nor a path gem's evaluated gemspec, which
      # Fledge wrote into its copy (PathPackage#copy_to), is the build's.
      def self.of(package, gem_dir)
        own = package.gem_files.merge(package.contents)
        fledges = package.is_a?(PathPackage) ? [package.gemspec] : [] # : Array[String]
        Entry.walk(gem_dir, prune: -> (folder) { File.basename(folder) == ".git" }).reject do |entry|
          entry.type == :directory || own[entry.path] == entry.content.to_s || fledges.include?(entry.path) || File.basename(entry.path) == ".git"
        end
      end

      # Those of +entries+, from ::of, that Ruby may load: each in one of
      # +folders+, the gem's require paths, and each shared library
      # elsewhere.
      def self.loaded(entries, folders)
        entries.select do |entry|
          folders.any? { |folder| entry.path.start_with?("#{folder}/") } || (entry.path.match?(LIBRARY) && !entry.path.match?(DEBUG))
        end
      end
    end
  end
end
