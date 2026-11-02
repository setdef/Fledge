# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"
require_relative "../git_gem"
require_relative "../locked_gem"
require_relative "../path_gem"

module Fledge
  class Bundle
    # Turns each locked specification into what Fledge ships for it, by
    # where the lockfile takes it from, and refuses what Fledge cannot
    # ship: a gem without a checksum, a git gem not pinned to a commit, and
    # a path gem whose folder is missing.
    class Sources # :nodoc:
      # Sources for the project at +root+, whose lockfile is named
      # +lockfile_name+ and has +checksums+, each gem's SHA-256 by the
      # name its CHECKSUMS section gives it.
      def initialize(root:, lockfile_name:, checksums:)
        @root = root
        @lockfile_name = lockfile_name
        @checksums = checksums
      end

      # What Fledge ships for +spec+ on +platform+: a gem from a gem
      # server, a gem from git, a gem from a folder that needs more than the
      # project's files, or +nil+ for one that ships with the project.
      def gem_for(spec, platform)
        source = spec.source
        case source
        when Bundler::Source::Rubygems then rubygem(spec, source, platform)
        when Bundler::Source::Git then git_gem(spec, source)
        when Bundler::Source::Path then own_gem(spec, source)
        else raise Error, "#{@lockfile_name} takes #{spec.name} from #{source}, and Fledge ships only gems from a gem server or from the project."
        end
      end

      # A gem from a gem server, asked as Bundler asks it:
      # Bundler::Source::Rubygems::Remote applies the mirror (<tt>bundle
      # config mirror.URL</tt>) and the login (<tt>bundle config HOST
      # USER:PASSWORD</tt>, or one in the Gemfile's source URL) that
      # Bundler's settings give, and Fledge keeps the login apart from the
      # address so that no message shows it.
      private def rubygem(spec, source, platform)
        platform_name = spec.platform.to_s
        lock_name = (platform_name == "ruby") ? "#{spec.name} (#{spec.version})" : "#{spec.name} (#{spec.version}-#{platform_name})"
        sha256 = @checksums[lock_name] or
          raise Error, "#{@lockfile_name} has no checksum for #{lock_name}, which #{platform} needs, and Fledge checks every gem " \
            "it ships. Run bundle lock --add-checksums, then build again."
        remote = Bundler::Source::Rubygems::Remote.new(source.remotes.first)
        LockedGem.new(name: spec.name, version: spec.version.to_s, platform: platform_name, remote: remote.anonymized_uri.to_s, sha256:,
          credentials: remote.uri.userinfo)
      end

      # A gem from git, at the revision the lockfile locks, which must be a
      # whole commit: SHA-1's 40 hexadecimal digits, or SHA-256's 64.
      private def git_gem(spec, source)
        revision = source.options["revision"].to_s
        unless revision.match?(/\A(?:\h{40}|\h{64})\z/)
          raise Error, "#{@lockfile_name} takes #{spec.name} from #{source.uri} without pinning it to a commit (its revision is " \
            "#{revision.inspect}), and Fledge ships a git gem only at the full commit the lockfile locks. Run bundle lock, then build again."
        end
        ref = %w[tag branch ref].filter_map { |kind| (value = source.options[kind]) && "#{kind} #{value}" }.first
        GitGem.new(name: spec.name, version: spec.version.to_s, uri: source.uri.to_s, revision:, glob: source.glob.to_s, ref:,
          submodules: !source.submodules.nil? && source.submodules != false)
      end

      # A gem from a folder (the project's own gemspec, or a path gem). One
      # inside the project, without an extension or an executable, ships as
      # part of the project (+nil+); so does the project's own gem, whose
      # executable is the program the app runs. Any other is a
      # Fledge::PathGem: one with an executable, whose wrapper Bundler writes
      # into the bundle's bin folder (Bundler::Source::Path#install, "and
      # installing its executables"), as Fledge writes it into the
      # runtime's; one with an extension, which Bundler compiles for no path gem (Bundler::Source::
      # Path#install generates its executables with extensions disabled), so
      # that what bundle exec loads is what the developer last compiled
      # there, for their own Ruby, and Fledge compiles for the runtime's;
      # and one outside the project, which ships where Bundler looks for a
      # copy of it (<tt>vendor/cache/NAME</tt>; Bundler::Source::Path#specs
      # and #has_app_cache?), as <tt>bundle cache --all</tt> would have put
      # it. The copy Bundler would use is the one in <tt>vendor/cache</tt>
      # when the developer has made it, and the original path otherwise.
      private def own_gem(spec, source)
        original = File.expand_path(source.options["path"].to_s, @root)
        inside = inside_project?(original)
        folder = inside ? original : copy_of(spec, original)
        gemspec = path_gemspec(folder, spec.name, source)
        return nil if inside && !gemspec&.extensions&.any? && (original == @root || !gemspec&.executables&.any?)

        app_path = inside ? relative_to_root(original) : outside_app_path(spec, original, source)
        PathGem.new(name: spec.name, version: spec.version.to_s, folder:, app_path:, glob: source.options["glob"] || GEMSPECS, inside:)
      end

      # (The lockfile's own spelling of the path is in +options+: once a
      # Bundler finds the copy in <tt>vendor/cache</tt>, its +path+ is that.)
      #
      # The folder bundle exec would load an outside path gem from: its copy
      # in the project's Bundler cache when there is one, and otherwise the
      # original path, which must exist.
      private def copy_of(spec, original)
        cached = File.join(Bundler.app_cache.to_s, File.basename(original))
        return cached if File.directory?(cached)
        return original if File.directory?(original)

        raise Error, "#{@lockfile_name} takes #{spec.name} from #{original}, outside the project, and that folder is not there. " \
          "Check out #{spec.name} there, or move it into the project, or take it from a gem server."
      end

      # Where a gem from outside the project goes in the built app, where
      # its Bundler looks for the copy it names by the last part of the
      # path (Bundler::Source::Path#app_cache_dirname).
      private def outside_app_path(spec, original, source)
        last = File.basename(source.options["path"].to_s)
        if [".", ".."].include?(last)
          raise Error, "#{@lockfile_name} takes #{spec.name} from #{source.options['path']}, outside the project, and a path that ends in " \
            "#{last.inspect} names no folder Fledge can put it in. Give the gem's folder its own name in the Gemfile's path:."
        end

        "#{Bundler.settings.app_cache_path}/#{File.basename(original)}"
      end

      private def relative_to_root(folder)
        (folder == @root) ? "." : folder.delete_prefix("#{@root}/")
      end

      # The gemspec named +name+ in the path gem folder +folder+, as Bundler
      # finds and evaluates it, or +nil+.
      private def path_gemspec(folder, name, source)
        Dir.glob(source.options["glob"] || GEMSPECS, base: folder).each do |file|
          spec = Bundler.load_gemspec(File.join(folder, file))
          return spec if spec&.name == name
        end
        nil
      end

      # The folder inside the project that +spec+ comes from, or +nil+ when
      # it is not a path gem in the project.
      def own_folder(spec)
        source = spec.source
        return nil unless source.is_a?(Bundler::Source::Path)

        folder = File.expand_path(source.options["path"].to_s, @root)
        folder if inside_project?(folder)
      end

      private def inside_project?(folder)
        folder == @root || folder.start_with?("#{@root}/")
      end
    end
  end
end
