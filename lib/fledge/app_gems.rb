# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "entry"
require_relative "error"
require_relative "gem_package"
require_relative "license_policy"

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
  # rest (Fledge::GemFetcher), and checks each one: its license, as its
  # specification declares it or as <tt>fledge.yml</tt> corrects it, and
  # whether it runs on the platform's runtime (Fledge::GemPackage). It
  # names every problem at once, then raises, so one build shows them
  # all. Otherwise it returns the entries that install each gem and
  # <tt>notices/GEMS.txt</tt>, which lists each gem, its license, and where
  # it came from, then holds the text of every license file it ships.
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
    def initialize(app:, bundle:, fetcher:)
      @app = app
      @bundle = bundle
      @fetcher = fetcher
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
      packages = locked.to_h { |gem| [gem, GemPackage.new(@fetcher.fetch(gem))] }
      problems = packages.flat_map do |gem, package|
        [*license_problem(gem, package), *package.problems(platform: platform.name, ruby_version: runtime.ruby_version)]
      end
      raise Error, "#{@app.name} can't ship for #{platform}:\n#{problems.map { |problem| "  #{problem}" }.join("\n")}" unless problems.empty?

      result(packages, platform, runtime)
    end

    private def result(packages, platform, runtime)
      return Result.new(files: [], warnings: []) if packages.empty?

      files = packages.values.flat_map { |package| package.entries(runtime.gem_dir) }
      warnings = packages.filter_map do |gem, package|
        "#{gem} ships no license file, so #{NOTICES} names its license but cannot quote it." if package.license_files.empty?
      end
      Result.new(files: [*files, Entry.file(NOTICES, notices(packages, platform, runtime))], warnings:)
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

    private def notices(packages, platform, runtime)
      summary = packages.map { |gem, package| entry(gem, package, runtime) }
      texts = packages.flat_map do |gem, package|
        package.license_files.map { |file, text| "#{'=' * 72}\n#{gem}: #{file}\n#{'=' * 72}\n\n#{text.b.force_encoding(Encoding::UTF_8).scrub}\n" }
      end
      <<~NOTICES
        THE APP'S OWN GEMS

        These are the gems #{@app.name}'s #{@bundle.lockfile_name} locks for #{platform},
        which fledge build added to Ruby's own, in #{runtime.gem_dir}. Ruby's own
        components and gems are in NOTICES.txt, beside this file.

        Each is listed with the license that its specification declares, or
        that the app's fledge.yml gives, where it came from, and the license
        files it ships, whose text follows. Fledge ships only gems whose
        licenses ask nothing beyond keeping their notices: keep this file
        with the app.

        #{summary.join("\n")}
        #{texts.join("\n")}
      NOTICES
    end

    private def entry(gem, package, runtime)
      spec = package.spec
      files = package.license_files.keys.map { |file| "#{runtime.gem_dir}/gems/#{spec.full_name}/#{file}" }
      corrected = @app.config.licenses.key?(gem.name) ? " (as fledge.yml gives it; the gem declares #{LicensePolicy.gem_license(spec.licenses)})" : ""
      <<~ENTRY
        #{gem}
          License: #{license(gem, package)}#{corrected}
          Homepage: #{spec.homepage || 'none given'}
          From: #{gem.url}
          License files: #{files.empty? ? 'none: the gem ships no license text' : files.join(', ')}
      ENTRY
    end
  end
end
