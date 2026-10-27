# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "compiled_code"
require_relative "entry"
require_relative "error"
require_relative "gem_package"
require_relative "git_checkout"
require_relative "git_package"
require_relative "license_policy"
require_relative "native_build"

module Fledge
  # The gems one platform's build of an app adds to its runtime, and what
  # they ask of the app's developer.
  #
  # Everything Fledge copies into an app, the developer gives away with
  # it, so an app's own gems meet the policy every runtime meets
  # (Fledge::LicensePolicy; decision 8 in
  # <tt>doc/contributors/decisions.md</tt>): a license that asks nothing
  # beyond keeping notices. The maintainer asked that app developers be
  # told plainly what they owe, so a gem that fails says so, naming the
  # gem, its license, and what to do, and each app carries its gems'
  # notices.
  #
  # This class takes the gems Fledge::Bundle locks for a platform, leaves
  # out those the runtime already has at the same version, fetches the
  # rest (Fledge::GemFetcher for a gem server's, Fledge::GitCheckout for
  # git's), compiles those with an extension still to compile when the
  # platform is the one Fledge runs on (Fledge::NativeBuild), and refuses
  # them for any other platform. Then it checks each one: its license, as
  # its specification declares it or as <tt>fledge.yml</tt> corrects it,
  # whether it runs on the platform's runtime, and what its compiled
  # files hold and need (Fledge::CompiledCode, with the Rust crates a
  # Rust extension compiled in), since a native gem's binaries can carry
  # libraries under licenses its specification does not name. It names
  # every problem at once, then raises, so one build shows them all.
  # Otherwise it returns the entries that install each gem and
  # <tt>notices/GEMS.txt</tt>, which lists each gem, its license, how it
  # was built, the libraries its compiled files hold, and where it came
  # from, then holds the text of every license file it ships.
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
  #   gems = Fledge::AppGems.new(app:, bundle: Fledge::Bundle.new(app), fetcher:)
  #   result = gems.for(Fledge::Platform.find("x86_64-linux"), runtime: Fledge::RuntimeContents.read(archive))
  #   result.files.last.path # => "notices/GEMS.txt"
  #--
  # SPDX-SnippetEnd
  #++
  class AppGems
    # Where the gems' notices go in a built app.
    NOTICES = "notices/GEMS.txt"

    # What one platform's build adds: the entries for the built folder,
    # and warnings for the developer.
    class Result < Data.define(:files, :warnings)
      ##
      # :attr_reader: files
      # The entries that install the gems, then their notices, with paths
      # relative to the built folder.

      ##
      # :attr_reader: warnings
      # Sentences about what Fledge could not do for the developer, such
      # as quote a gem's license when it ships no license file.
    end

    # Creates the planner.
    #
    # [app] The Fledge::App, whose <tt>fledge.yml</tt> may correct a gem's
    #       license.
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

    # The gems +platform+'s build adds to the runtime +runtime+ (its
    # Fledge::RuntimeContents). Raises Fledge::Error naming every gem that
    # cannot ship, and why.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   gems.for(Fledge::Platform.find("x64-mingw-ucrt"), runtime: contents).warnings # => []
    #--
    # SPDX-SnippetEnd
    #++
    def for(platform, runtime:)
      locked = @bundle.gems_for(platform, ruby_version: runtime.ruby_version).reject { |gem| runtime.gems.include?(gem.full_name) }
      packages, uncompiled = compile(platform, locked.to_h { |gem| [gem, package_for(gem)] })
      code = CompiledCode.new(declared: @app.config.compiled, os: platform.os, provided: runtime.libraries)
      compiled = packages.to_h do |gem, package|
        [gem, code.audit(gem.name, package.contents, label: gem.to_s, crates: package.is_a?(CompiledGem) ? package.crates&.compiled : nil)]
      end
      problems = packages.flat_map do |gem, package|
        [
          *license_problem(gem, package),
          *uncompiled.fetch(gem, []),
          *package.problems(ruby_version: runtime.ruby_version),
          *compiled.fetch(gem).problems,
          *build_crate_problems(gem, package),
]
      end
      raise Error, "#{@app.name} can't ship for #{platform}:\n#{problems.map { |problem| "  #{problem}" }.join("\n")}" unless problems.empty?

      result(packages, compiled, platform, runtime)
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

    private def result(packages, compiled, platform, runtime)
      return Result.new(files: [], warnings: []) if packages.empty?

      files = packages.values.flat_map { |package| package.entries(runtime.gem_dir) }.uniq(&:path)
      warnings = packages.filter_map do |gem, package|
        "#{gem} ships no license file, so #{NOTICES} names its license but cannot quote it." if package.license_files.empty?
      end
      Result.new(files: [*files, Entry.file(NOTICES, notices(packages, compiled, platform, runtime))], warnings:)
    end

    # The license that decides, and whether it came from fledge.yml.
    private def license(gem, package)
      @app.config.licenses.fetch(gem.name) { LicensePolicy.gem_license(package.spec.licenses) }
    end

    private def license_problem(gem, package)
      expression = license(gem, package)
      return [] if LicensePolicy.notice_only?(expression)

      said = (expression == "NOASSERTION") ? "declares no license" : "is #{expression}"
      [
"#{gem} #{said}, and Fledge ships only gems whose licenses ask nothing beyond keeping their notices (doc/licensing.md). " \
  "If its license is another, give it in fledge.yml, under licenses, such as licenses: {#{gem.name}: MIT}.",
]
    end

    private def notices(packages, compiled, platform, runtime)
      summary = packages.map { |gem, package| entry(gem, package, compiled.fetch(gem).components, runtime) }
      shared = compiled.values.flat_map(&:components).select { |component| component.shared && component.source }
      texts = packages.flat_map do |gem, package|
        package.license_files.map { |file, text| "#{'=' * 72}\n#{gem}: #{file}\n#{'=' * 72}\n\n#{text.b.force_encoding(Encoding::UTF_8).scrub}\n" }
      end
      <<~NOTICES
        THE APP'S OWN GEMS

        These are the gems #{@app.name}'s #{@bundle.lockfile_name} locks for #{platform},
        which fledge build added to Ruby's own, in #{runtime.gem_dir}. Ruby's own
        components and gems are in NOTICES.txt, beside this file.

        Each is listed with the license that its specification declares, or
        that the app's fledge.yml gives, the libraries its compiled files
        hold and their licenses, where it came from, and the license files
        it ships, whose text follows. Fledge ships only gems whose licenses
        ask nothing beyond keeping their notices, and LGPL libraries only as
        separate shared libraries: keep this file with the app.
        #{lgpl(shared)}
        #{summary.join("\n")}
        #{texts.join("\n")}
      NOTICES
    end

    private def entry(gem, package, components, runtime)
      spec = package.spec
      files = package.license_files.keys.map { |file| "#{package.installed_path(runtime.gem_dir)}/#{file}" }
      corrected = @app.config.licenses.key?(gem.name) ? " (as fledge.yml gives it; the gem declares #{LicensePolicy.gem_license(spec.licenses)})" : ""
      <<~ENTRY
        #{gem}
          License: #{license(gem, package)}#{corrected}
        #{built_line(package, runtime)}#{components.map { |component| "  #{component_line(component)}\n" }.join}  Homepage: #{spec.homepage || 'none given'}
          From: #{gem.url}
          License files: #{files.empty? ? 'none: the gem ships no license text' : files.join(', ')}
      ENTRY
    end

    # The Rust crates that ran while +package+ compiled whose licenses ask
    # more than notices. Their code writes some of what is compiled in, so
    # they meet the policy too, as cargo-deny checks every crate.
    private def build_crate_problems(gem, package)
      return [] unless package.is_a?(CompiledGem)

      (package.crates&.build || []).reject { |crate| LicensePolicy.notice_only?(crate.license) }.map do |crate|
        said = (crate.license == "NOASSERTION") ? "declares no license" : "is #{crate.license}"
        "#{gem} is built with the #{crate.name}, which #{said}, and Fledge builds gems only with code whose license asks " \
          "nothing beyond keeping its notices (doc/licensing.md)."
      end
    end

    # How a gem Fledge compiled was built, as GEMS.txt says it, with the
    # Rust crates that ran only while it compiled.
    private def built_line(package, runtime)
      return "" unless package.is_a?(CompiledGem)

      options = package.build_args.empty? ? "" : ", with the build options #{package.build_args.join(' ')}"
      tools = (package.crates&.build || []).map { |crate| "  Built with: #{crate.name} (#{crate.license}), which ran only while it compiled\n" }
      "  Built: compiled from source by fledge build, against the runtime's Ruby #{runtime.ruby_version}#{options}\n#{tools.join}"
    end

    # One library a gem's compiled files hold, as GEMS.txt lists it.
    private def component_line(component)
      license = "#{component.license}#{', as fledge.yml gives it' if component.declared}"
      where = component.files.join(", ")
      return "Compiled in: #{component.name} (#{license}), in #{where}" unless component.shared

      "Shared library: #{component.name} (#{license}), #{where}, which whoever receives the app may replace" \
        "#{"; its source: #{component.source}" if component.source}"
    end

    # What the LGPL asks of a developer whose app ships LGPL libraries as
    # their own shared libraries, or nothing when it ships none.
    private def lgpl(shared)
      return "" if shared.empty?

      <<~LGPL

        Some of these gems ship an LGPL library as its own shared library,
        listed below as a shared library with where its exact source is. The
        LGPL asks you to keep this notice, to give whoever receives the app
        that source or a written offer of it, to let them replace the library
        with their own build, and to allow reverse engineering of the app for
        debugging such a replacement (LGPL-2.1, sections 6 and 7; LGPL-3.0,
        section 4). It asks nothing of your own code. doc/licensing.md says
        more; ask your own lawyer what applies to you.
      LGPL
    end
  end
end
