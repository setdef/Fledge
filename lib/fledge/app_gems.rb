# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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
require_relative "mobile_extensions"
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
  # git's), and compiles those with an extension still to compile for a
  # desktop, whose platform is the one Fledge runs on
  # (Fledge::NativeBuild); a phone's extensions are compiled for its
  # project (Fledge::MobileExtensions), which refuses only one it does
  # not compile there. Then it checks that each one runs on the
  # platform's runtime: its <tt>required_ruby_version</tt>, what its
  # compiled files need (Fledge::Linkage), and, for what Fledge compiled,
  # the oldest macOS or glibc it needs. It names every problem at once,
  # then raises, so one build shows them all. Otherwise it returns the
  # entries that install each gem, each with its own files, license files
  # among them, where RubyGems or Bundler would put them, except a
  # RubyGems plugin loader the runtime already has for a gem of that
  # name at another version (rdoc, which irb asks for): the runtime's
  # stays, and the build does not fail on the clash
  # (doc/contributors/design/gems.md, "RubyGems plugin loaders").
  #
  # Use it once per target in <tt>fledge build</tt>.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   gems = Fledge::AppGems.new(app:, bundle: Fledge::Bundle.new(app), fetcher:, checkouts:, compiler:)
  #   entries = gems.for(Fledge::Platform.find("x86_64-linux"), runtime: Fledge::RuntimeContents.read(archive))
  #   entries.map(&:path).grep(/sqlite3_native/) # => ["lib/ruby/gems/4.1.0+5/gems/sqlite3-2.10.2/lib/sqlite3/sqlite3_native.so"]
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
      @bundler = nil # : String?
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
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gems.for(Fledge::Platform.find("x64-mingw-ucrt"), runtime: contents).first.path
    #   # => "ruby/lib/ruby/gems/4.1.0+5/gems/concurrent-ruby-1.3.8"
    #--
    # SPDX-SnippetEnd
    #++
    def for(platform, runtime:)
      locked = @bundle.gems_for(platform, ruby_version: runtime.ruby_version, arch: runtime.arch) { |gem| required_ruby(gem) }
        .reject { |gem| !gem.is_a?(PathGem) && runtime.gems.include?(gem.full_name) }
      bundler = locked_bundler(runtime)
      @bundler = bundler&.version
      locked << bundler if bundler
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

      packages = mark_extensions(packages, platform, runtime) if platform.is_a?(MobilePlatform)
      entries = [*packages.flat_map { |gem, package| entries_for(gem, package, runtime.gem_dir) }, *stubs]
      entries.uniq(&:path).reject { |entry| runtime.plugins.include?(entry.path) }
    end

    # The version of the Bundler #for added to the runtime, which the app
    # runs with in place of the runtime's own, as <tt>bundle exec</tt>
    # runs the Bundler its lockfile names (Fledge::Bundle#bundler_for), or
    # +nil+ when it runs the runtime's own: +nil+ before #for.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # Gemfile.lock: BUNDLED WITH 4.0.19, and the runtime's Bundler is 4.0.20
    #   gems.for(Fledge::Platform.find("x86_64-linux"), runtime: contents)
    #   gems.bundler # => "4.0.19"
    #--
    # SPDX-SnippetEnd
    #++
    attr_reader :bundler

    # The Bundler the lockfile names in place of +runtime+'s own, as a
    # Fledge::LockedGem, or +nil+ for the runtime's, or for a runtime
    # with no Bundler at all.
    private def locked_bundler(runtime)
      running = runtime.gems.filter_map { |name| name[/\Abundler-(\d[^-]*)\z/, 1] }.first or return nil

      @bundle.bundler_for(running, ruby_version: runtime.ruby_version) { |gem| required_ruby(gem) }
    end

    # The wrappers of the executables of the gems in +packages+, as the
    # runtime's RubyGems writes them (Fledge::NativeBuild#binstubs), in the
    # runtime's bin folder, where it keeps its own gems'
    # (doc/contributors/design/gems.md, "Gem executables"): all but
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
    # the Ruby it asks for, and what its compiled files need; and on
    # Linux, each library <tt>fledge.yml</tt> lists as the distribution's
    # that none of them needs (Config::Linux; ADR 030).
    private def desktop_problems(packages, platform, runtime)
      readers(platform, runtime) do |readers|
        linkage = Linkage.new(os: platform.libraries, provided: runtime.libraries, system: @app.config.system_libraries(platform.os), readers:)
        found = packages.flat_map do |gem, package|
          [*package.problems(ruby_version: runtime.ruby_version), *linkage.problems(gem.to_s, package.contents)]
        end
        [*found, *linkage.unused]
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
        # is left is the system's temporary folder's to clear
        # (doc/contributors/design/runtimes.md, "Windows on ARM64").
        FileUtils.rm_rf(dir)
      end
    end

    # What keeps each gem from running on a phone: the Ruby it asks for,
    # and an extension Fledge does not compile there
    # (Fledge::MobileExtensions.problems).
    private def mobile_problems(packages, platform, runtime)
      packages.flat_map do |gem, package|
        [*package.problems(ruby_version: runtime.ruby_version), *MobileExtensions.problems(gem, package, platform, @compiler.platform)]
      end
    end

    # +packages+ with each gem from a server or git that has an extension
    # marked built, as RubyGems and Bundler mark one they compiled
    # (<tt>gem.build_complete</tt> in its extension folder, for each
    # platform of the phone's Ruby), so that neither ignores the gem for
    # its extensions not being built: the extension itself is linked into
    # the app (Fledge::MobileExtensions), not in a file. A path gem is
    # not marked, as a desktop's is not (#entries_for).
    private def mark_extensions(packages, platform, runtime)
      @extension_packages = packages.select { |_, package| package.extensions? }
      api = "#{File.basename(runtime.gem_dir)}-static"
      packages.to_h do |gem, package|
        root, folder = extension_folder(package, api)
        next [gem, package] unless package.extensions? && root && !package.is_a?(CompiledGem)

        marks = platform.gem_platforms.flat_map { |name| extension_marks(format(folder.to_s, name)) }
        [gem, CompiledGem.new(package:, built: [], extensions: marks, extension_dir: root, build_args: [], build_info: nil, problems: [])]
      end
    end

    # Where RubyGems (for a gem from a server) and Bundler (for one from
    # git) keep a built gem's extensions: the folder below the gem folder
    # that holds them all, and the path below it with a <tt>%s</tt> for
    # the platform; neither for a path gem.
    private def extension_folder(package, api)
      case package
      when GemPackage then ["extensions", "%s/#{api}/#{package.spec.full_name}"]
      when GitPackage then ["bundler/gems/extensions", "%s/#{api}/#{package.scope}"]
      end
    end

    # The entries below the extension folder for +path+: each of its
    # folders, and the empty file that marks it built.
    private def extension_marks(path)
      parts = path.split("/")
      [*(1..(parts.size)).map { |count| Entry.directory(parts.first(count).join("/")) }, Entry.file("#{path}/gem.build_complete", "")]
    end

    # The gems with an extension that fledge build linked into the app,
    # as #for found them, by gem, for Fledge::MobileExtensions to compile:
    # empty before #for, and for a desktop.
    def extension_packages
      @extension_packages ||= {} # : Hash[locked_gem, package]
    end

    # The build options the app's Bundler settings give each of the
    # gems of #extension_packages, by gem name.
    def extension_build_args
      extension_packages.keys.to_h { |gem| [gem.name, @bundle.build_args(gem.name)] }
    end

    # The Ruby versions +gem+'s build admits, from its <tt>.gem</tt>, as
    # Bundler reads them from its source to choose between a gem's builds
    # (Fledge::Bundle#gems_for).
    private def required_ruby(gem)
      Gem::Package.new(@fetcher.fetch(gem)).spec.required_ruby_version
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
