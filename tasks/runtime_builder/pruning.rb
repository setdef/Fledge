# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "rubygems"

class RuntimeBuilder
  # What a runtime leaves out of the Ruby it is made from (ADR 003): what
  # no running Ruby code reads, and what a standard Ruby does not
  # install.
  module Pruning
    # Removes, from a copy of a Ruby's lib/ruby at +ruby+, what no running
    # Ruby code reads, and what a standard Ruby 4.0.9 does not install.
    # Returns the names of the executables of the gems it removed, for
    # prune_bin. +bundled+ names Ruby's bundled gems, from
    # runtime/sources.yml. Each removal, and why no app can miss it:
    #
    # [*.dSYM] macOS debug symbols, read by debuggers and crash reporters,
    #          never by Ruby.
    # [*.a, *.h, pkgconfig] Static libraries, C headers, and pkg-config
    #          files, for compiling against Ruby; a runtime compiles
    #          nothing, and Ruby code never loads them.
    # [gems/4.0.0/doc] RDoc and ri documentation, read by the rdoc and ri
    #          tools a developer runs, never by an app's requires.
    # [portable_ruby_gems.rb, and gems no standard Ruby installs] rv-ruby's
    #          own additions (a load-path helper for its executables, and
    #          bootsnap and msgpack): a standard Ruby 4.0.9, and
    #          RubyInstaller's, has none of them, so an app that worked
    #          under ruby never needed them. Gems that are neither default
    #          gems nor in +bundled+ go, with their specification, cache,
    #          build information, and extensions.
    #
    # Everything else stays: the standard library, every default and
    # bundled gem, each gem's executables, the .gem cache (gem pristine and
    # Gem::Specification#cache_file read it), build information, plugins,
    # and C extensions.
    def self.prune(ruby, bundled)
      FileUtils.rm_rf(Dir.glob(File.join(ruby, "**", "*.dSYM")))
      FileUtils.rm_f(Dir.glob(File.join(ruby, "*", "*", "portable_ruby_gems.rb")))
      FileUtils.rm_f(Dir.glob(File.join(ruby, "**", "*.{a,h}")))
      FileUtils.rm_rf(Dir.glob(File.join(ruby, "**", "pkgconfig")))
      Dir.glob(File.join(ruby, "gems", "*")).flat_map { |gems| prune_gems(gems, bundled) }
    end

    # Removes the documentation, and every gem that is neither a default
    # gem nor one of +bundled+, from the gem folder +gems+. Returns the
    # removed gems' executables.
    def self.prune_gems(gems, bundled)
      FileUtils.rm_rf(File.join(gems, "doc"))
      prune_jruby(gems)
      Dir.glob(File.join(gems, "specifications", "*.gemspec")).flat_map do |path|
        spec = Gem::Specification.load(path) or raise "#{path} is not a gem specification"
        next [] if bundled.include?(spec.name)

        remove_gem(gems, spec.full_name)
        spec.executables
      end
    end

    def self.remove_gem(gems, full_name)
      FileUtils.rm_f(File.join(gems, "specifications", "#{full_name}.gemspec"))
      FileUtils.rm_rf(File.join(gems, "gems", full_name))
      FileUtils.rm_f(File.join(gems, "cache", "#{full_name}.gem"))
      FileUtils.rm_f(File.join(gems, "build_info", "#{full_name}.info"))
      FileUtils.rm_rf(Dir.glob(File.join(gems, "extensions", "*", "*", full_name)))
    end

    # Files of CRuby's gems that only JRuby reads, by gem: nkf's ext/java,
    # the Java sources of JRuby's nkf, which CRuby never compiles or loads
    # (nkf.gemspec builds them only for the java platform, and ext/nkf is
    # CRuby's). They are EPL-2.0 OR LGPL-2.1-or-later, the only copyleft
    # text in a runtime besides license data (runtime/licenses.yml).
    JRUBY_ONLY = { "nkf" => "ext/java/" }.freeze

    # Removes JRUBY_ONLY's files from the gem folder +gems+: from each
    # gem's installed folder, and from its .gem in the cache, which holds
    # them too (GemRepack.repack).
    def self.prune_jruby(gems)
      JRUBY_ONLY.each do |name, folder|
        Dir.glob(File.join(gems, "gems", "#{name}-*", folder)).each { |path| FileUtils.rm_rf(path) }
        Dir.glob(File.join(gems, "cache", "#{name}-*.gem")).each { |path| GemRepack.repack(path, folder) }
      end
    end

    # Removes from +bin+ the executables of gems prune removed, which
    # would fail without their gem.
    def self.prune_bin(bin, executables)
      executables.each { |name| FileUtils.rm_f(File.join(bin, name)) }
    end

    # Removes, from a copy of RubyInstaller's tree at +tree+, what no
    # running Ruby code reads, as prune does for lib\ruby, and
    # RubyInstaller's own tools for setting up a developer's computer:
    #
    # [share\] Ruby's HTML documentation and ri data, for the rdoc and ri
    #          tools.
    # [include\, lib\*.a, lib\pkgconfig] Headers and import libraries,
    #          for compiling against Ruby.
    # [packages\, ridk_use\, bin\ridk.cmd, bin\ridk.ps1,
    #          bin\setrbvars.cmd, bin\startmenu.rb] The MSYS2 keyring and
    #          ridk, which install and select MSYS2 compilers for a
    #          developer, and the scripts that set up a developer's shell
    #          and the Start menu; they work only beside an installed
    #          RubyInstaller and MSYS2.
    #
    # Every program and DLL stays (ruby.exe and rubyw.exe for RbConfig.ruby
    # and Gem.ruby, and the DLLs some extension's manifest names), and so
    # do the gems' command-line wrappers (gem.cmd, bundle.bat, ...) and
    # RubyInstaller's own Ruby library in site_ruby.
    def self.prune_windows(tree, bundled)
      FileUtils.rm_rf(%w[share include packages ridk_use lib/pkgconfig].map { |path| File.join(tree, path) })
      FileUtils.rm_f(Dir.glob(File.join(tree, "lib", "*.a")))
      FileUtils.rm_f(%w[ridk.cmd ridk.ps1 setrbvars.cmd startmenu.rb].map { |name| File.join(tree, "bin", name) })
      prune_bin(File.join(tree, "bin"), prune(File.join(tree, "lib", "ruby"), bundled))
    end
  end
end
