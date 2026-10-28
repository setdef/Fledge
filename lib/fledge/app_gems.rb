# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "entry"
require_relative "error"
require_relative "gem_package"
require_relative "git_checkout"
require_relative "git_package"
require_relative "linkage"
require_relative "native_build"

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
  # them for any other platform. Then it checks that each one runs on the
  # platform's runtime: its <tt>required_ruby_version</tt>, what its
  # compiled files need (Fledge::Linkage), and, for what Fledge compiled,
  # the oldest macOS or glibc it needs. It names every problem at once,
  # then raises, so one build shows them all. Otherwise it returns the
  # entries that install each gem, each with its own files, license files
  # among them, where RubyGems or Bundler would put them.
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
  #   gems = Fledge::AppGems.new(app:, bundle: Fledge::Bundle.new(app), fetcher:, checkouts:)
  #   entries = gems.for(Fledge::Platform.find("x86_64-linux"), runtime: Fledge::RuntimeContents.read(archive))
  #   entries.map(&:path).grep(/sqlite3_native/) # => ["lib/ruby/gems/4.0.0/gems/sqlite3-2.10.2-x86_64-linux-gnu/lib/sqlite3/4.0/sqlite3_native.so"]
  #--
  # SPDX-SnippetEnd
  #++
  class AppGems
    # Creates the planner.
    #
    # [app] The Fledge::App.
    # [bundle] Its Fledge::Bundle.
    # [fetcher] The Fledge::GemFetcher that finds each gem's file.
    # [checkouts] The Fledge::GitCheckout that fetches each git gem.
    # [compiler] The Fledge::NativeBuild for the platform Fledge runs on,
    #            or +nil+ when Fledge has no runtime for it.
    def initialize(app:, bundle:, fetcher:, checkouts:, compiler: nil)
      @app = app
      @bundle = bundle
      @fetcher = fetcher
      @checkouts = checkouts
      @compiler = compiler
    end

    # What the app's +app+ folder holds in place of the project's own
    # files: Fledge::Bundle#app_files.
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
    def app_files
      @bundle.app_files
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
      locked = @bundle.gems_for(platform, ruby_version: runtime.ruby_version, arch: runtime.arch).reject { |gem| runtime.gems.include?(gem.full_name) }
      packages, uncompiled = compile(platform, locked.to_h { |gem| [gem, package_for(gem)] })
      linkage = Linkage.new(os: platform.os, provided: runtime.libraries)
      problems = packages.flat_map do |gem, package|
        [
          *uncompiled.fetch(gem, []),
          *package.problems(ruby_version: runtime.ruby_version),
          *linkage.problems(gem.to_s, package.contents),
]
      end
      raise Error, "#{@app.name} can't ship for #{platform}:\n#{problems.map { |problem| "  #{problem}" }.join("\n")}" unless problems.empty?

      packages.values.flat_map { |package| package.entries(runtime.gem_dir) }.uniq(&:path)
    end

    private def package_for(gem)
      case gem
      when LockedGem then GemPackage.new(@fetcher.fetch(gem))
      else GitPackage.new(gem, @checkouts.checkout(gem))
      end
    end

    # The packages with each extension compiled, when +platform+ is the
    # one Fledge runs on, and otherwise why each gem with an extension
    # cannot ship, by gem.
    private def compile(platform, packages)
      uncompiled = packages.select { |_, package| package.extensions? }
      none = {} # : Hash[locked_gem, Array[String]]
      return [packages, none] if uncompiled.empty?

      compiler = @compiler
      if compiler && compiler.platform == platform
        [compiler.call(packages, build_args: uncompiled.keys.to_h { |gem| [gem.name, @bundle.build_args(gem.name)] }), none]
      else
        [packages, uncompiled.keys.to_h { |gem| [gem, [cross_problem(gem, platform, compiler&.platform)]] }]
      end
    end

    private def cross_problem(gem, platform, host)
      this = host ? "this computer is #{host}" : "Fledge has no runtime for this computer"
      "#{gem} has an extension to compile, and the lockfile locks no build of it precompiled for #{platform}. Fledge compiles " \
        "a gem only on the platform it is for, and #{this}: build for #{platform} on a computer that is #{platform}, such as " \
        "a CI runner of that platform, or choose a version of #{gem.name} with a build for #{platform} and run bundle lock " \
        "--add-platform #{platform}."
    end
  end
end
