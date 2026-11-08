# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "bundler"
require "fileutils"
require_relative "app"
require_relative "command"
require_relative "config"
require_relative "entry"
require_relative "error"
require_relative "mac_bundle"
require_relative "platform"
require_relative "runtimes"
require_relative "version"
require_relative "assembly"

module Fledge
  # An app <tt>fledge build</tt> wrote, which <tt>fledge build --from</tt>
  # builds another app from (ADR 032, section 2).
  #
  # A built app already holds a runtime and the gems its Gemfile.lock
  # locks, each built for its platform. A project that needs no other
  # gems becomes an app by copying it, as electron-builder's
  # <tt>--prepackaged</tt> packages an Electron already laid out and
  # LÖVE's fused game is a copy of LÖVE: nothing is downloaded, resolved,
  # or compiled.
  #
  # This class reads the app's <tt>fledge.cfg</tt>, whose first line names
  # the Fledge release and the platform that built it
  # (Assembly#launch_config), and refuses an app another release built,
  # since its launcher and its <tt>fledge.cfg</tt> are that release's, or
  # one for another platform (ADR 032, section 6). It hands
  # Fledge::Assembly what a runtime archive would give (#unpack): the
  # app's runtime and gems, without its project, its <tt>fledge.cfg</tt>,
  # its programs, or the files that carry its identity; and the files
  # Bundler needs to set up the app's gems for another project (#files):
  # its Gemfile and lockfile, its <tt>.bundle</tt> settings, Bundler's
  # <tt>vendor/cache</tt>, and the folders inside its project that its
  # lockfile takes gems from. On Windows a program carries its app's
  # identity in its resources, which rcedit adds to but cannot take away,
  # so a new program and rcedit come from the app's own tools folder, which
  # an app built with +build_tools+ carries (Assembly::BuildTools), or else
  # from the runtime this Fledge would use, when this computer has it
  # (Runtimes#at_hand), and never from a download. The tools folder of the
  # app stays behind: a new app carries one only when it asks.
  #
  # Use it through <tt>fledge build --from</tt>.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   from = Fledge::BuiltApp.at("dist/Player-x86_64-linux", platform: Fledge::Platform.local, runtimes: Fledge::Runtimes.new)
  #   app = from.adopt(Fledge::App.at("game"))
  #   app.gemfile # => "Gemfile"
  #--
  # SPDX-SnippetEnd
  #++
  class BuiltApp
    # The first line of a <tt>fledge.cfg</tt> this Fledge wrote, with the
    # release and the platform it names.
    HEADER = /\A# Written by fledge build (\S+) for (\S+):/

    # The lockfile Bundler keeps beside each name a Gemfile may have.
    LOCKFILES = { "Gemfile" => "Gemfile.lock", "gems.rb" => "gems.locked" }.freeze

    # What <tt>fledge build --from</tt> says to a project that has gems
    # of its own.
    GEMS = "--from builds no gems: build this project with fledge build"

    # The app <tt>fledge build</tt> wrote at +path+, the folder it wrote
    # or, on macOS, its <tt>.app</tt>, for +platform+, the computer's,
    # whose runtime +runtimes+ may have at hand. Raises Fledge::Error
    # when it is not one, another Fledge release built it, or it is for
    # another platform.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::BuiltApp.at("dist/Player-x86_64-linux", platform: Fledge::Platform.local, runtimes: Fledge::Runtimes.new).path
    #   # => "/home/you/dist/Player-x86_64-linux"
    #--
    # SPDX-SnippetEnd
    #++
    def self.at(path, platform:, runtimes:)
      full = File.expand_path(path)
      raise Error, "--from #{path} is not a folder. Give it the folder of an app fledge build wrote, such as dist/NAME-PLATFORM." unless File.directory?(full)

      bundle = bundle_in(full)
      contents = bundle ? File.join(bundle, "Contents", "Resources") : full
      config = File.join(contents, Assembly::CONFIG)
      raise Error, "--from #{path} is not an app fledge build wrote: it has no #{Assembly::CONFIG}" unless File.file?(config)

      new(given: path, contents:, bundle:, config: File.read(config), platform:, runtimes:)
    end

    # The <tt>.app</tt> that is +folder+, or the one it holds, whose
    # Resources hold a <tt>fledge.cfg</tt>; +nil+ for any other folder.
    private_class_method def self.bundle_in(folder) # :nodoc:
      return nil if File.file?(File.join(folder, Assembly::CONFIG))

      candidates = folder.end_with?(".app") ? [folder] : Dir.glob("*.app", base: folder).map { |name| File.join(folder, name) }
      found = candidates.select { |bundle| File.file?(File.join(bundle, "Contents", "Resources", Assembly::CONFIG)) }
      found.first if found.size == 1
    end

    # Reads the app whose runtime and project are in +contents+, inside
    # +bundle+ when it is one, as +config+, its <tt>fledge.cfg</tt>, says.
    def initialize(given:, contents:, bundle:, config:, platform:, runtimes:)
      @given = given
      @contents = contents
      @bundle = bundle
      @platform = platform
      @runtimes = runtimes
      check(config[HEADER, 1], config[HEADER, 2])
      @gemfile = config[/^gemfile = (.+)$/, 1]
      @system_libraries = config[/^system_libraries = (.+)$/, 1].to_s.split
      @identifiers = config.scan(/^identifier = (.+)$/).flatten
      @programs = config.scan(/^\[(.+)\]$/).flatten
      @programs = [bundle ? File.basename(bundle, ".app") : File.basename(contents).delete_suffix("-#{platform}")] if @programs.empty?
      raise Error, "--from #{given} is not an app fledge build wrote: it has no program #{@programs.first}" unless File.file?(program)
    end

    # The app's folder, as the person gave it.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   from.path # => "dist/Player-x86_64-linux"
    #--
    # SPDX-SnippetEnd
    #++
    def path
      @given
    end

    # +app+, the project to build, as an app built from this one: with
    # this app's Gemfile, and on Linux the system libraries its gems load.
    # Raises Fledge::Error when the project has gems of its own, a
    # <tt>fledge.yml</tt> key that changes the runtime or the gems, or a
    # file where this app keeps one Bundler needs, or when this app's own
    # project is one of its gems.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   from.adopt(Fledge::App.at("game")).gemfile # => "Gemfile"
    #--
    # SPDX-SnippetEnd
    #++
    def adopt(app)
      root = app.root
      raise Error, GEMS if app.gemfile || !Dir.glob("*.gemspec", base: root).empty?

      config = app.config
      libraries = config.system_libraries("linux")
      key = {
"programs" => config.programs,
"linux: system_libraries" => (libraries unless libraries.empty?),
"ios" => config.ios,
"android" => config.android,
}.find { |_, value| value }&.first
      if key
        raise Error, "#{File.join(root, Config::FILE)} has #{key}, which changes the runtime or the gems, and --from keeps #{@given}'s. " \
          "Build this project with fledge build."
      end

      (kept - App::NEVER_SHIPPED).each do |path|
        full = File.join(root, path)
        raise Error, "#{root} holds #{path}, which --from takes from #{@given}. Remove it, or build with fledge build." if File.exist?(full) || File.symlink?(full)
      end
      changelog = config.linux&.deb_changelog
      linux = Config::Linux.new(system_libraries: @system_libraries, deb_changelog: changelog) unless @system_libraries.empty? && changelog.nil?
      app.with(gemfile: @gemfile, config: config.with(linux:))
    end

    # The entries of the built app's +app+ folder that set up its gems,
    # with paths relative to the folder that holds it, as
    # Fledge::Assembly takes them: the Gemfile, its lockfile, Bundler's
    # settings and cache, and each folder inside the project the lockfile
    # takes a gem from. Raises Fledge::Error when the project is itself one
    # of the gems.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   from.files.map(&:path).first(2) # => ["app/Gemfile", "app/Gemfile.lock"]
    #--
    # SPDX-SnippetEnd
    #++
    def files
      kept.flat_map do |path|
        full = File.join(project, path)
        next [Entry.file("app/#{path}", File.binread(full), mode: File.executable?(full) ? 0o755 : 0o644)] unless File.directory?(full)

        [Entry.directory("app/#{path}"), *Entry.walk(full).map { |entry| entry.with(path: "app/#{path}/#{entry.path}") }]
      end
    end

    # What the app holds for a new app named +app_names+, as an unpacked
    # runtime gives it (Fledge::Assembly::RuntimeFolder), with +work+ for
    # what it unpacks or copies. Raises Fledge::Error on Windows when the
    # runtime is not at hand.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   from.unpack(app_names: ["Game"], work: Dir.mktmpdir).tools # => nil
    #--
    # SPDX-SnippetEnd
    #++
    def unpack(app_names:, work:)
      own = own_tools
      return Tree.new(self, launchers: own_launchers(own, work), tools: own, app_names:) if own

      archive = @runtimes.at_hand(@platform)
      if archive.nil? && @platform.windows?
        raise Error, "--from takes a Windows app's launchers and rcedit from the tools folder of an app built with build_tools: true, " \
          "which #{@given} has not, or else from Fledge #{VERSION}'s runtime for #{@platform}, which this computer has not: " \
          "put #{Runtimes.file_name(@platform)} in FLEDGE_RUNTIME_DIR or #{@runtimes.cache}."
      end

      only = [Assembly::LAUNCHER, Assembly::WINDOWED_LAUNCHER].map { |name| @platform.executable(name) } + [Assembly::TOOLS]
      runtime = archive && Assembly::RuntimeFolder.new(archive, platform: @platform, app_names:, work:, only:)
      return Tree.new(self, launchers: -> (name) { runtime.launcher(name) }, tools: runtime.tools, app_names:) if runtime

      copy = launcher_copy(work)
      Tree.new(self, launchers: -> (_name) { copy }, tools: nil, app_names:)
    end

    # The app's own tools folder, which an app built with +build_tools+
    # holds (Assembly::BuildTools), when it has what <tt>--from</tt>
    # needs of it here: on Windows, the launchers too.
    private def own_tools
      folder = File.join(@contents, Assembly::TOOLS)
      return nil unless File.directory?(folder)
      return folder unless @platform.windows?

      launchers = [Assembly::LAUNCHER, Assembly::WINDOWED_LAUNCHER].map { |name| File.join(folder, @platform.executable(name)) }
      folder if launchers.all? { |launcher| File.file?(launcher) }
    end

    # The launchers in the app's own tools +folder+: on Windows, the ones
    # it carries; elsewhere, a copy of its program in +work+.
    private def own_launchers(folder, work)
      return -> (name) { File.join(folder, @platform.executable(name)) } if @platform.windows?

      copy = launcher_copy(work)
      -> (_name) { copy }
    end

    # Copies everything of the app into +folder+ but its project, its
    # <tt>fledge.cfg</tt>, its programs, and the files that carry its
    # identity: the runtime, the gems, and the notices. Raises
    # Fledge::Error when one of +app_names+ would collide with them.
    def copy_into(folder, app_names) # :nodoc:
      FileUtils.mkdir_p(folder)
      held.each do |name|
        taken = app_names.find { |app_name| name.casecmp?(@platform.executable(app_name)) }
        raise Error, "an app named #{taken} would collide with #{@given}'s #{name}. Give it another name." if taken

        FileUtils.copy_entry(File.join(@contents, name), File.join(folder, name), true)
      end
      @identifiers.each { |identifier| remove_icons(folder, identifier) }
    end

    # The names in the app's folder that a new app keeps: not its tools
    # folder, which the new app holds only if it asks for its own.
    private def held
      programs = @programs.map { |name| @platform.executable(name) }
      identity = @identifiers.map { |identifier| "#{identifier}.desktop" }
      identity << "#{File.basename(@bundle.to_s, '.app')}.icns" if @bundle
      Dir.children(@contents).sort - ["app", Assembly::CONFIG, Assembly::TOOLS] - programs - identity
    end

    # Removes a Linux app's icons, named by its +identifier+, from +folder+
    # and the folders they leave empty.
    private def remove_icons(folder, identifier)
      Dir.glob("share/icons/hicolor/*/apps/#{identifier}.png", base: folder).each do |icon|
        File.delete(File.join(folder, icon))
        parent = File.dirname(icon)
        while parent != "." && Dir.empty?(File.join(folder, parent))
          Dir.rmdir(File.join(folder, parent))
          parent = File.dirname(parent)
        end
      end
    end

    # A copy, in +work+, of the app's program, which is the runtime's
    # launcher: on macOS signed again ad hoc, so that it carries no
    # signature of the app's.
    private def launcher_copy(work)
      copy = File.join(work, "launcher", @platform.executable(Assembly::LAUNCHER))
      FileUtils.mkdir_p(File.dirname(copy))
      FileUtils.cp(program, copy, preserve: true)
      Command.run("codesign", "--force", "--sign", "-", copy, install: MacBundle::INSTALL) if @platform.os == "darwin"
      copy
    end

    # The app's main program.
    private def program
      bundle = @bundle
      return File.join(bundle, "Contents", "MacOS", File.basename(bundle, ".app")) if bundle

      File.join(@contents, @platform.executable(@programs.fetch(0)))
    end

    # The app's project folder.
    private def project
      File.join(@contents, "app")
    end

    # The paths, relative to the project, that set up the app's gems.
    private def kept
      gemfile = @gemfile
      return [] unless gemfile

      lockfile = LOCKFILES.fetch(gemfile, "#{gemfile}.lock")
      paths = [gemfile, lockfile, ".bundle", "vendor/cache", *gem_folders(File.join(project, lockfile))]
      paths.uniq.select { |path| File.exist?(File.join(project, path)) }
    end

    # The folders inside the project that the lockfile at +lockfile+ takes
    # gems from. Raises Fledge::Error for the project's own folder.
    private def gem_folders(lockfile)
      parser = Bundler::LockfileParser.new(File.read(lockfile))
      parser.sources.filter_map do |source|
        next if source.is_a?(Bundler::Source::Git) || !source.is_a?(Bundler::Source::Path)

        folder = Pathname.new(source.options["path"].to_s).cleanpath.to_s
        if folder == "."
          names = parser.specs.select { |spec| spec.source == source }.map(&:name)
          raise Error, "#{@given}'s #{File.basename(lockfile)} takes #{names.join(', ')} from its project's own folder, which --from replaces. " \
            "Build this project with fledge build."
        end
        folder unless folder.start_with?("../", "/") || folder == ".."
      end
    end

    # Refuses an app that +version+ of Fledge built for +platform+, unless
    # they are this Fledge and this computer's platform.
    private def check(version, platform)
      unless version == VERSION
        by = version ? "Fledge #{version}" : "an earlier Fledge"
        raise Error, "--from #{@given} was built by #{by}, and this is Fledge #{VERSION}. Build from an app this Fledge built."
      end
      return if platform == @platform.name

      raise Error, "--from #{@given} is an app for #{platform}, and this computer builds for #{@platform}. Build from an app for this computer."
    end

    # A built app's runtime and gems, as Fledge::Assembly takes an
    # unpacked runtime: its launchers, its tools, and what the new app
    # holds of it.
    class Tree # :nodoc:
      # The tree of +built_app+, whose launcher named +name+ is
      # <tt>launchers.call(name)</tt>, and whose tools folder is +tools+.
      def initialize(built_app, launchers:, tools:, app_names:)
        @built_app = built_app
        @launchers = launchers
        @tools = tools
        @app_names = app_names
      end

      # The launcher named +name+.
      def launcher(name)
        @launchers.call(name)
      end

      # The tools folder, or +nil+.
      attr_reader :tools

      # Copies the app's runtime and gems into +folder+.
      def move_into(folder)
        @built_app.copy_into(folder, @app_names)
      end
    end
  end
end
