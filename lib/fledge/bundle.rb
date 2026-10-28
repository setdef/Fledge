# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "shellwords"
require_relative "error"
require_relative "git_gem"
require_relative "locked_gem"

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
    # <tt>arm64-darwin-24</tt> does not. Raises Fledge::Error, saying what to run, when
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
      target = Gem::Platform.new(arch)
      check_ruby(ruby_version)
      check_locked(platform, target)
      chosen(platform, ruby_version, target).filter_map { |spec| locked_gem(spec, platform) }.sort_by(&:name)
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

      raise Error, "#{lockfile_name} locks no gems for #{platform}. Run bundle lock --add-platform #{platform}, then build again."
    end

    # The locked specifications the app's dependencies reach on
    # +platform+, each the one Bundler would choose there.
    private def chosen(platform, ruby_version, target)
      lookup = @definition.locked_gems.specs.group_by(&:name)
      queue = @definition.dependencies.select { |dependency| ships?(dependency, platform, ruby_version) }
        .map { |dependency| [dependency.name, dependency.force_ruby_platform || false] } # : Array[[String, bool]]
      seen = {} # : Hash[String, bool]
      specs = [] # : Array[Bundler::LazySpecification]
      while (name, force_ruby = queue.shift)
        next if seen[name] || name == "bundler"

        seen[name] = true
        spec = best(lookup, name, target, force_ruby, platform)
        specs << spec
        spec.dependencies.each { |dependency| queue << [dependency.name, false] unless dependency.type == :development }
      end
      specs
    end

    private def best(lookup, name, target, force_ruby, platform)
      candidates = lookup[name] or raise Error, "#{lockfile_name} locks no #{name}. Run bundle lock, then build again."
      Bundler::MatchPlatform.select_best_platform_match(candidates, target, force_ruby:).first or
        raise Error, "#{lockfile_name} locks no build of #{name} for #{platform}, only for " \
          "#{candidates.map { |spec| spec.platform.to_s }.sort.join(', ')}. If #{name} has one, run bundle lock " \
          "--add-platform #{platform}, then build again."
    end

    # Whether the dependency is one Bundler sets up on +platform+, outside
    # WITHOUT's groups.
    private def ships?(dependency, platform, ruby_version)
      return false if (dependency.groups - WITHOUT).empty?
      return false unless dependency.should_include && dependency.current_env?

      dependency.platforms.empty? || dependency.platforms.any? { |name| on_platform?(name.to_s, platform, ruby_version) }
    end

    # Whether a Gemfile's <tt>platforms:</tt> name holds on +platform+,
    # as Bundler::CurrentRuby answers it on that platform's runtime, a
    # CRuby: +windows+ (and its old names +mswin+, +mingw+, and
    # +x64_mingw+) on Windows, +ruby+ and +mri+ everywhere else, never
    # +jruby+ or +truffleruby+, each with an optional Ruby version, such
    # as +mri_40+.
    private def on_platform?(name, platform, ruby_version)
      base, digits = name.match(/\A(.+?)(?:_(\d+))?\z/)&.captures
      holds = case base
              when "windows", "mswin", "mswin64", "mingw", "x64_mingw" then platform.windows?
              when "ruby", "mri" then !platform.windows?
              else false
      end
      holds && (digits.nil? || ruby_version.start_with?("#{digits.to_s.chars.join('.')}."))
    end

    private def locked_gem(spec, platform)
      source = spec.source
      case source
      when Bundler::Source::Rubygems then rubygem(spec, source, platform)
      when Bundler::Source::Git then git_gem(spec, source)
      when Bundler::Source::Path then own_gem(spec, source)
      else raise Error, "#{lockfile_name} takes #{spec.name} from #{source}, and Fledge ships only gems from a gem server or from the project."
      end
    end

    private def rubygem(spec, source, platform)
      platform_name = spec.platform.to_s
      lock_name = (platform_name == "ruby") ? "#{spec.name} (#{spec.version})" : "#{spec.name} (#{spec.version}-#{platform_name})"
      sha256 = @checksums[lock_name] or
        raise Error, "#{lockfile_name} has no checksum for #{lock_name}, which #{platform} needs, and Fledge checks every gem " \
          "it ships. Run bundle lock --add-checksums, then build again."
      LockedGem.new(name: spec.name, version: spec.version.to_s, platform: platform_name, remote: source.remotes.first.to_s, sha256:)
    end

    # A gem from git, at the revision the lockfile locks, which must be a
    # whole commit: SHA-1's 40 hexadecimal digits, or SHA-256's 64.
    private def git_gem(spec, source)
      revision = source.options["revision"].to_s
      unless revision.match?(/\A(?:\h{40}|\h{64})\z/)
        raise Error, "#{lockfile_name} takes #{spec.name} from #{source.uri} without pinning it to a commit (its revision is " \
          "#{revision.inspect}), and Fledge ships a git gem only at the full commit the lockfile locks. Run bundle lock, then build again."
      end
      if source.submodules
        raise Error, "#{lockfile_name} takes #{spec.name} from #{source.uri} with its submodules, which Fledge does not fetch yet. " \
          "Release it to a gem server, or take it from git without submodules."
      end

      ref = %w[tag branch ref].filter_map { |kind| (value = source.options[kind]) && "#{kind} #{value}" }.first
      GitGem.new(name: spec.name, version: spec.version.to_s, uri: source.uri.to_s, revision:, glob: source.glob.to_s, ref:)
    end

    # A gem from a folder (the project's own gemspec, or a path gem), which
    # ships as part of the project when the folder is inside it, unless
    # its gemspec has an extension to compile: Bundler compiles no path
    # gem's extension (Bundler::Source::Path#install generates its
    # executables with extensions disabled), so what bundle exec loads is
    # what the developer last compiled there, for their own Ruby.
    private def own_gem(spec, source)
      folder = File.expand_path(source.path.to_s, @app.root)
      if inside_project?(folder)
        if path_gemspec(folder, spec.name)&.extensions&.any?
          raise Error, "#{lockfile_name} takes #{spec.name} from #{folder}, a folder inside the project, and its gemspec has an " \
            "extension to compile, which Bundler does not compile for a path gem (bundle exec loads whatever was last compiled " \
            "there, for your own Ruby). Take it from git or a gem server, so Fledge can compile it for the runtime's Ruby."
        end
        return nil
      end

      raise Error, "#{lockfile_name} takes #{spec.name} from #{folder}, outside the project, and Fledge ships only what is " \
        "inside #{@app.root}. Move it into the project, or take it from a gem server."
    end

    # The gemspec named +name+ in the path gem folder +folder+, as Bundler
    # finds and evaluates it, or +nil+.
    private def path_gemspec(folder, name)
      Dir.glob(GEMSPECS, base: folder).each do |file|
        spec = Bundler.load_gemspec(File.join(folder, file))
        return spec if spec&.name == name
      end
      nil
    end

    private def inside_project?(folder)
      folder == @app.root || folder.start_with?("#{@app.root}/")
    end

    # What the built app's +app+ folder holds in place of the project's
    # own files, by path relative to it: Bundler's settings for the app
    # (SETTINGS, as <tt>.bundle/config</tt>), and each gemspec of the
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
    def app_files
      gemspecs = own_folders.flat_map { |folder| Dir.glob(GEMSPECS, base: folder).map { |name| File.join(folder, name) } }
      gemspecs.uniq.sort.each_with_object({ ".bundle/config" => SETTINGS }) do |path, files|
        spec = Bundler.load_gemspec(path) or next
        spec.installed_by_version = Gem::VERSION
        files[path.delete_prefix("#{@app.root}/")] = spec.to_ruby
      end
    end

    private def own_folders
      @definition.locked_gems.specs.filter_map do |spec|
        source = spec.source
        next unless source.is_a?(Bundler::Source::Path)

        folder = File.expand_path(source.path.to_s, @app.root)
        folder if inside_project?(folder)
      end.uniq
    end
  end
end
