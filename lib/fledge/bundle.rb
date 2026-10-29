# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "shellwords"
require_relative "error"
require_relative "git_gem"
require_relative "locked_gem"
require_relative "bundle/selection"
require_relative "bundle/sources"

module Fledge
  # What an app's Gemfile and Gemfile.lock say it ships, for each
  # platform.
  #
  # A developer runs a gem-shaped app as <tt>bundle exec exe/my_cool_app</tt>:
  # Bundler puts the project's own <tt>lib</tt> and every gem its
  # Gemfile.lock locks on the load path. A built app does the same, with
  # Bundler, so the app's code stays as it is (decision 9 in
  # <tt>doc/contributors/decisions.md</tt>; ADR 005). For that, each
  # target's runtime needs the very gems Bundler would choose on that
  # target, which a Gemfile.lock records for every platform it lists, as
  # <tt>bundle lock --add-platform</tt> and <tt>bundle cache
  # --all-platforms</tt> rely on.
  #
  # This class reads the Gemfile and its lockfile with Bundler itself,
  # refuses a lockfile the Gemfile has moved past (as Bundler refuses one
  # in frozen mode), and, for a platform, picks each gem the lockfile
  # locks for it as Bundler picks one at run time
  # (Bundler::MatchPlatform), leaving out the +development+ and +test+
  # groups, as Warbler and <tt>bundle install --without</tt> do, and gems
  # the Gemfile limits to other platforms. A gem from git comes at the
  # revision the lockfile locks (Fledge::GitGem). It refuses what it
  # cannot ship: a platform the lockfile does not lock, a git gem the
  # lockfile does not pin to a commit, a gem from a folder outside the
  # project, a path gem with an extension to compile, a gem without a
  # checksum, and a Gemfile that asks for another Ruby. It also reads the
  # build options Bundler would pass each gem's extension
  # (<tt>bundle config build.NAME</tt>).
  #
  # Use it in <tt>fledge build</tt> for an app with a Gemfile.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   bundle = Fledge::Bundle.new(Fledge::App.at("examples/my_cool_app"))
  #   bundle.gems_for(Fledge::Platform.find("x64-mingw-ucrt"), ruby_version: "4.0.9", arch: "x64-mingw-ucrt").map(&:to_s)
  #   # => ["concurrent-ruby 1.3.8", "i18n 1.15.2", "sqlite3 2.10.2 (x64-mingw-ucrt)"]
  #--
  # SPDX-SnippetEnd
  #++
  class Bundle
    # The groups a built app leaves out, as Warbler's bundle_without does
    # (Warbler::Config, <tt>bundle_without</tt>, development and test).
    WITHOUT = %i[development test].freeze

    # Bundler's settings for the built app, in its .bundle/config, the
    # level of Bundler's settings that wins over every other
    # (Bundler::Settings#configs), which the launcher also has Bundler
    # read in place of the person's ~/.bundle/config. They are Warbler's
    # for a packed app (Warbler::Traits::Bundler, BUNDLE_CONFIG_DEFAULTS):
    # never switch to another Bundler (version: system), refuse a Gemfile
    # that has moved past its lockfile and never rewrite or touch the
    # lockfile (frozen), take the gems from Ruby's own gem folder, where
    # fledge build put them (path.system), and never install at boot
    # (auto_install); and Fledge's own: leave out WITHOUT, whose gems the
    # app does not ship.
    SETTINGS = <<~YAML
      ---
      BUNDLE_VERSION: "system"
      BUNDLE_FROZEN: "true"
      BUNDLE_PATH__SYSTEM: "true"
      BUNDLE_AUTO_INSTALL: "false"
      BUNDLE_WITHOUT: "#{WITHOUT.join(':')}"
    YAML

    # The setting a phone's app adds to SETTINGS: Bundler's own
    # <tt>force_ruby_platform</tt>, which it documents as "Ignore the
    # current machine's platform and install only <tt>ruby</tt> platform
    # gems" (<tt>lib/bundler/man/bundle-config.1.ronn</tt>, at Bundler
    # 4.0.20), so that an iOS Ruby, which reports <tt>arm64-darwin</tt>,
    # never resolves a macOS gem (ADR 011, section 1).
    FORCE_RUBY_PLATFORM = "BUNDLE_FORCE_RUBY_PLATFORM: \"true\"\n"

    # Where Bundler finds a path gem's gemspecs (Bundler::Source::Path,
    # DEFAULT_GLOB).
    GEMSPECS = "{,*,*/*}.gemspec"

    # Reads +app+'s Gemfile and lockfile. Raises Fledge::Error when there
    # is no lockfile, when Bundler cannot read either, or when the
    # lockfile is out of date.
    def initialize(app)
      require "bundler"
      @app = app
      gemfile = File.join(app.root, app.gemfile.to_s)
      @lockfile = (File.basename(gemfile) == "gems.rb") ? File.join(app.root, "gems.locked") : "#{gemfile}.lock"
      unless File.file?(@lockfile)
        raise Error, "#{app.root} has #{app.gemfile} but no #{File.basename(@lockfile)}. Run bundle lock, then build again."
      end

      @build_args = {} # : Hash[String, Array[String]]
      @definition = definition(gemfile)
      @checksums = checksums(File.read(@lockfile))
    end

    # The options Bundler would pass +name+'s extension when it compiles
    # it, from <tt>bundle config build.NAME</tt> at any level Bundler
    # reads (the project's <tt>.bundle/config</tt>, BUNDLE_BUILD__NAME,
    # or the developer's own), split as a shell would, as
    # Bundler::GemInstaller#spec_settings splits them.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   # bundle config build.nokogiri --use-system-libraries
    #   bundle.build_args("nokogiri") # => ["--use-system-libraries"]
    #--
    # SPDX-SnippetEnd
    #++
    def build_args(name)
      @build_args.fetch(name, [])
    end

    # The lockfile's name, such as <tt>Gemfile.lock</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.lockfile_name # => "Gemfile.lock"
    #--
    # SPDX-SnippetEnd
    #++
    def lockfile_name
      File.basename(@lockfile)
    end

    private def definition(gemfile)
      at_project(gemfile) do
        dsl = Bundler::Dsl.new
        dsl.eval_gemfile(gemfile)
        definition = dsl.to_definition(Pathname.new(@lockfile), {})
        Bundler.settings.temporary(frozen: true) { definition.ensure_equivalent_gemfile_and_lockfile(true) }
        @build_args = build_settings
        definition
      end
    rescue Bundler::BundlerError => e
      raise Error, "Bundler can't read #{gemfile} and #{lockfile_name}:\n#{e.message}"
    end

    # Every build.NAME setting Bundler has, by NAME.
    private def build_settings
      settings = Bundler.settings
      settings.all.filter_map do |key|
        next unless key.start_with?("build.")

        [key.delete_prefix("build."), Shellwords.shellsplit(settings[key].to_s)]
      end.to_h
    end

    # Runs the block with Bundler's root at the app's project, as
    # BUNDLE_GEMFILE puts it for bundle commands, then puts Bundler back
    # where it was. Bundler reads a lockfile's path gems relative to its
    # root (Bundler::Source::Path#root), which in fledge build's own
    # process is wherever fledge build runs, often its own bundle.
    private def at_project(gemfile)
      saved = ENV.fetch("BUNDLE_GEMFILE", nil)
      ENV["BUNDLE_GEMFILE"] = gemfile
      Bundler.reset_settings_and_root!
      yield
    ensure
      ENV["BUNDLE_GEMFILE"] = saved
      Bundler.reset_settings_and_root!
    end

    # The SHA-256 of each gem in the lockfile's CHECKSUMS section, by the
    # name the section gives it, such as <tt>sqlite3 (2.10.2-arm64-darwin)</tt>.
    private def checksums(text)
      section = text[/^CHECKSUMS\n((?:  .*\n)*)/, 1].to_s
      section.scan(/^  (\S+ \([^)]+\)) sha256=([0-9a-f]{64})\b/).to_h { |name, sha256| [name.to_s, sha256.to_s] }
    end

    # The gems from a gem server or from git that +platform+'s app ships:
    # each gem the lockfile locks for +platform+ that the app's
    # dependencies reach, leaving out Bundler, the project's own gems,
    # WITHOUT's groups, and gems the Gemfile limits to other platforms.
    # +ruby_version+ is the runtime's Ruby, for a dependency limited to
    # some Ruby versions, and +arch+ its architecture (RbConfig's), whose
    # RubyGems platform is the one the built app's Bundler runs as, so a
    # lockfile platform and a gem's build fit +platform+ exactly when they
    # would fit there (Bundler::Definition#current_platform_locked? and
    # Gem::Platform#===): <tt>arm64-darwin</tt> and
    # <tt>arm64-darwin-23</tt> fit rv-ruby's <tt>arm64-darwin23</tt>, and
    # <tt>arm64-darwin-24</tt> does not. A Fledge::MobilePlatform's app
    # runs Bundler with <tt>force_ruby_platform</tt> (ADR 011, section 1),
    # as which the lockfile must lock +ruby+, and each gem is its +ruby+
    # build. Raises Fledge::Error, saying what to run, when
    # the lockfile does not lock +platform+, the Gemfile asks for another
    # Ruby, a git gem is not pinned to a commit or needs its submodules, a
    # gem comes from a folder outside the project or is a path gem with an
    # extension, or a gem has no checksum.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.gems_for(Fledge::Platform.find("x86_64-linux"), ruby_version: "4.0.9", arch: "x86_64-linux").last.platform
    #   # => "x86_64-linux-gnu"
    #--
    # SPDX-SnippetEnd
    #++
    def gems_for(platform, ruby_version:, arch:)
      target = Gem::Platform.new(platform.force_ruby_platform? ? Gem::Platform::RUBY : arch)
      check_ruby(ruby_version)
      check_locked(platform, target)
      specs = Selection.new(@definition, lockfile_name:, platform:, ruby_version:, target:).specs
      specs.filter_map { |spec| sources.gem_for(spec, platform) }.sort_by(&:name)
    end

    private def check_ruby(ruby_version)
      wanted = @definition.ruby_version or return
      return unless wanted.diff(Bundler::RubyVersion.new([ruby_version], nil, "ruby", ruby_version))

      raise Error, "#{@app.gemfile} asks for Ruby #{wanted.versions.join(', ')}, and Fledge's runtimes are Ruby #{ruby_version}."
    end

    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: MIT
    # SPDX-SnippetCopyrightText: 2010-2019 André Arko, 2009 Engine Yard
    # SPDX-SnippetComment: Bundler::Definition#validate_platforms! and
    #   #current_platform_locked?, adapted from bundler/definition.rb at
    #   Bundler 4.0.20 (lines 524 to 530 and 832 to 836), with the
    #   runtime's platform as Bundler's local one.
    #++
    private def check_locked(platform, target)
      locked = @definition.platforms
      return if locked.any? { |candidate| candidate.to_s == "ruby" || Gem::Platform.generic(target) == candidate || target === candidate }
      #--
      # SPDX-SnippetEnd
      #++

      raise Error, "#{lockfile_name} locks no gems for #{platform}. Run bundle lock --add-platform #{platform.lockfile_names.first}, " \
        "then build again."
    end

    # What the built app's +app+ folder holds in place of the project's
    # own files, by path relative to it: Bundler's settings for the app
    # (SETTINGS, as <tt>.bundle/config</tt>, with FORCE_RUBY_PLATFORM when
    # +force_ruby_platform+ is true, for a phone), and each gemspec of the
    # project's own gems, evaluated now, as Bundler caches a git gem's
    # gemspecs evaluated so that one that runs git keeps working without
    # it (Bundler::Source::Git#serialize_gemspecs_in).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.app_files.keys # => [".bundle/config", "my_cool_app.gemspec"]
    #--
    # SPDX-SnippetEnd
    #++
    def app_files(force_ruby_platform: false)
      settings = force_ruby_platform ? "#{SETTINGS}#{FORCE_RUBY_PLATFORM}" : SETTINGS
      gemspecs = own_folders.flat_map { |folder| Dir.glob(GEMSPECS, base: folder).map { |name| File.join(folder, name) } }
      gemspecs.uniq.sort.each_with_object({ ".bundle/config" => settings }) do |path, files|
        spec = Bundler.load_gemspec(path) or next
        spec.installed_by_version = Gem::VERSION
        files[path.delete_prefix("#{@app.root}/")] = spec.to_ruby
      end
    end

    private def own_folders
      @definition.locked_gems.specs.filter_map { |spec| sources.own_folder(spec) }.uniq
    end

    private def sources
      @sources ||= Sources.new(root: @app.root, lockfile_name:, checksums: @checksums)
    end
  end
end
