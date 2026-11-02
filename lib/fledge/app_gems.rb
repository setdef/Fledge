# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tmpdir"
require_relative "binary"
require_relative "entry"
require_relative "error"
require_relative "gem_package"
require_relative "git_checkout"
require_relative "git_package"
require_relative "linkage"
require_relative "mobile_platform"
require_relative "native_build"
require_relative "path_gem"
require_relative "path_package"

module Fledge
  # The gems one platform's build of an app adds to its runtime.
  #
  # An app's gems are its developer's choice, and so are their licenses:
  # Fledge ships whatever the app's Gemfile.lock locks, under whatever
  # license, and takes no position on it (the maintainer's words of
  # 2026-10-28 in <tt>doc/contributors/decisions.md</tt>; ADR 007). What
  # it does check is whether each gem will run where the app goes, since
  # a person who runs the app must never meet an error that names a gem.
  #
  # This class takes the gems Fledge::Bundle locks for a platform, leaves
  # out those the runtime already has at the same version, fetches the
  # rest (Fledge::GemFetcher for a gem server's, Fledge::GitCheckout for
  # git's), compiles those with an extension still to compile when the
  # platform is the one Fledge runs on (Fledge::NativeBuild), and refuses
  # them for any other platform, and for a phone (Fledge::MobilePlatform),
  # whose gems must be pure Ruby until after 1.0. Then it checks that each one runs on the
  # platform's runtime: its <tt>required_ruby_version</tt>, what its
  # compiled files need (Fledge::Linkage), and, for what Fledge compiled,
  # the oldest macOS or glibc it needs. It names every problem at once,
  # then raises, so one build shows them all. Otherwise it returns the
  # entries that install each gem, each with its own files, license files
  # among them, where RubyGems or Bundler would put them, except a
  # RubyGems plugin loader the runtime already has for a gem of that
  # name at another version (rdoc, which irb asks for): the runtime's
  # stays, and the build does not fail on the clash (ADR 019).
  #
  # Use it once per target in <tt>fledge build</tt>.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   gems = Fledge::AppGems.new(app:, bundle: Fledge::Bundle.new(app), fetcher:, checkouts:, compiler:)
  #   entries = gems.for(Fledge::Platform.find("x86_64-linux"), runtime: Fledge::RuntimeContents.read(archive))
  #   entries.map(&:path).grep(/sqlite3_native/) # => ["lib/ruby/gems/4.0.0/gems/sqlite3-2.10.2-x86_64-linux-gnu/lib/sqlite3/4.0/sqlite3_native.so"]
  #--
  # SPDX-SnippetEnd
  #++
  class AppGems
    # The llvm-readobj a Windows runtime keeps in its tools folder.
    READOBJ = "llvm-readobj.exe"

    # Creates the planner.
    #
    # [app] The Fledge::App.
    # [bundle] Its Fledge::Bundle.
    # [fetcher] The Fledge::GemFetcher that finds each gem's file.
    # [checkouts] The Fledge::GitCheckout that fetches each git gem.
    # [compiler] The Fledge::NativeBuild that compiles gems for the
    #            platform Fledge runs on, which is the one it builds for.
    def initialize(app:, bundle:, fetcher:, checkouts:, compiler:)
      @app = app
      @bundle = bundle
      @fetcher = fetcher
      @checkouts = checkouts
      @compiler = compiler
      @path_files = {} # : Hash[String, String]
    end

    # What the app's +app+ folder holds in place of the project's own
    # files: Fledge::Bundle#app_files, with Bundler's
    # <tt>force_ruby_platform</tt> when +force_ruby_platform+ is true, as
    # for a phone; and the files #for compiled for the project's own path
    # gems, which replace the ones the developer compiled for their Ruby, so
    # ask after #for.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gems.app_files.keys # => [".bundle/config", "my_cool_app.gemspec"]
    #--
    # SPDX-SnippetEnd
    #++
    def app_files(force_ruby_platform: false)
      @bundle.app_files(force_ruby_platform:).merge(@path_files)
    end

    # The entries, with paths relative to the built folder, that install
    # the gems +platform+'s build adds to the runtime +runtime+ (its
    # Fledge::RuntimeContents). Raises Fledge::Error naming every gem that
    # would not run there, and why.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gems.for(Fledge::Platform.find("x64-mingw-ucrt"), runtime: contents).first.path
    #   # => "ruby/lib/ruby/gems/4.0.0/gems/concurrent-ruby-1.3.8"
    #--
    # SPDX-SnippetEnd
    #++
    def for(platform, runtime:)
      locked = @bundle.gems_for(platform, ruby_version: runtime.ruby_version, arch: runtime.arch)
        .reject { |gem| !gem.is_a?(PathGem) && runtime.gems.include?(gem.full_name) }
      packages = locked.to_h { |gem| [gem, package_for(gem)] } # : Hash[locked_gem, package]
      stubs = [] # : Array[Entry]
      problems = case platform
      when MobilePlatform then mobile_problems(packages, platform, runtime)
      else
        packages = compile(packages)
        stubs = executables(packages, runtime)
        desktop_problems(packages, platform, runtime)
      end
      raise Error, "#{@app.name} can't ship for #{platform}:\n#{problems.map { |problem| "  #{problem}" }.join("\n")}" unless problems.empty?

      entries = [*packages.flat_map { |gem, package| entries_for(gem, package, runtime.gem_dir) }, *stubs]
      entries.uniq(&:path).reject { |entry| runtime.plugins.include?(entry.path) }
    end

    # The wrappers of the executables of the gems in +packages+, as the
    # runtime's RubyGems writes them (Fledge::NativeBuild#binstubs), in the
    # runtime's bin folder, where it keeps its own gems' (ADR 020): all but
    # a program the runtime already has under that name, whose wrapper
    # finds whichever version of its gem the app's Bundler activates.
    private def executables(packages, runtime)
      @compiler.binstubs(packages).values.flatten.map { |entry| entry.with(path: "#{runtime.bin_dir}/#{entry.path}") }
        .reject { |entry| runtime.binaries.include?(entry.path) }
    end

    # The entries that install +gem+ (as +package+, compiled or not) in a
    # built app whose runtime's gem folder is +gem_dir+. A path gem is not
    # installed in the gem folder: Bundler loads it from the folder the
    # lockfile names, in the app, so one outside the project ships whole in
    # Bundler's place for a copy of it, and one inside has what was
    # compiled for it noted as files that replace the project's own.
    private def entries_for(gem, package, gem_dir)
      path = package.is_a?(CompiledGem) ? package.package : package
      return package.entries(gem_dir) unless gem.is_a?(PathGem) && path.is_a?(PathPackage)

      built = package.is_a?(CompiledGem) ? package.built : [] # : Array[Entry]
      return path.app_entries(built) unless gem.inside

      @path_files.merge!(path.app_files(built))
      []
    end

    # What keeps each gem from running on a desktop +platform+'s runtime:
    # the Ruby it asks for, and what its compiled files need.
    private def desktop_problems(packages, platform, runtime)
      readers(platform, runtime) do |readers|
        linkage = Linkage.new(os: platform.libraries, provided: runtime.libraries, readers:)
        packages.flat_map do |gem, package|
          [*package.problems(ruby_version: runtime.ruby_version), *linkage.problems(gem.to_s, package.contents)]
        end
      end
    end

    # Yields the tools that read +platform+'s compiled files
    # (Fledge::Binary::Readers): on Windows, which has none of its own,
    # the llvm-readobj the runtime carries (ADR 013).
    private def readers(platform, runtime)
      return yield Binary::Readers.local(platform.os) unless platform.windows?

      dir = Dir.mktmpdir("fledge-readobj")
      begin
        yield Binary::Readers.local(platform.os, readobj: runtime.tool(READOBJ, into: dir))
      ensure
        # Windows on ARM's x86-64 emulator may hold llvm-readobj.exe open
        # for a while after it exits, as with makensis (Fledge::Nsis); what
        # is left is the system's temporary folder's to clear (ADR 018).
        FileUtils.rm_rf(dir)
      end
    end

    # What keeps each gem from running on a phone: the Ruby it asks for,
    # and an extension, which Fledge does not compile for a phone; native
    # gems on phones come after 1.0 (Plan 002).
    private def mobile_problems(packages, platform, runtime)
      packages.flat_map do |gem, package|
        native = package.extensions? ? [native_problem(gem, platform)] : [] # : Array[String]
        [*package.problems(ruby_version: runtime.ruby_version), *native]
      end
    end

    private def native_problem(gem, platform)
      "#{gem} has an extension to compile, and Fledge ships only pure-Ruby gems to #{platform} for now; native gems on " \
        "phones come after Fledge 1.0. Leave it out of the app's #{platform} build (gem \"#{gem.name}\", platforms: [...] " \
        "in the Gemfile), or find a pure-Ruby gem in its place."
    end

    private def package_for(gem)
      case gem
      when LockedGem then GemPackage.new(@fetcher.fetch(gem))
      when PathGem then PathPackage.new(gem)
      else GitPackage.new(gem, @checkouts.checkout(gem))
      end
    end

    # The packages, with each one that has an extension compiled.
    private def compile(packages)
      uncompiled = packages.select { |_, package| package.extensions? }
      return packages if uncompiled.empty?

      @compiler.call(packages, build_args: uncompiled.keys.to_h { |gem| [gem.name, @bundle.build_args(gem.name)] })
    end
  end
end
