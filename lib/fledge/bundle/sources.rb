# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"
require_relative "../git_gem"
require_relative "../locked_gem"

module Fledge
  class Bundle
    # Turns each locked specification into what Fledge ships for it, by
    # where the lockfile takes it from, and refuses what Fledge cannot
    # ship: a gem without a checksum, a git gem not pinned to a commit or
    # that needs its submodules, and a gem from a folder outside the
    # project or with an extension to compile.
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
      # server, a gem from git, or +nil+ for one of the project's own.
      def gem_for(spec, platform)
        source = spec.source
        case source
        when Bundler::Source::Rubygems then rubygem(spec, source, platform)
        when Bundler::Source::Git then git_gem(spec, source)
        when Bundler::Source::Path then own_gem(spec, source)
        else raise Error, "#{@lockfile_name} takes #{spec.name} from #{source}, and Fledge ships only gems from a gem server or from the project."
        end
      end

      private def rubygem(spec, source, platform)
        platform_name = spec.platform.to_s
        lock_name = (platform_name == "ruby") ? "#{spec.name} (#{spec.version})" : "#{spec.name} (#{spec.version}-#{platform_name})"
        sha256 = @checksums[lock_name] or
          raise Error, "#{@lockfile_name} has no checksum for #{lock_name}, which #{platform} needs, and Fledge checks every gem " \
            "it ships. Run bundle lock --add-checksums, then build again."
        LockedGem.new(name: spec.name, version: spec.version.to_s, platform: platform_name, remote: source.remotes.first.to_s, sha256:)
      end

      # A gem from git, at the revision the lockfile locks, which must be a
      # whole commit: SHA-1's 40 hexadecimal digits, or SHA-256's 64.
      private def git_gem(spec, source)
        revision = source.options["revision"].to_s
        unless revision.match?(/\A(?:\h{40}|\h{64})\z/)
          raise Error, "#{@lockfile_name} takes #{spec.name} from #{source.uri} without pinning it to a commit (its revision is " \
            "#{revision.inspect}), and Fledge ships a git gem only at the full commit the lockfile locks. Run bundle lock, then build again."
        end
        if source.submodules
          raise Error, "#{@lockfile_name} takes #{spec.name} from #{source.uri} with its submodules, which Fledge does not fetch yet. " \
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
        folder = File.expand_path(source.path.to_s, @root)
        if inside_project?(folder)
          if path_gemspec(folder, spec.name)&.extensions&.any?
            raise Error, "#{@lockfile_name} takes #{spec.name} from #{folder}, a folder inside the project, and its gemspec has an " \
              "extension to compile, which Bundler does not compile for a path gem (bundle exec loads whatever was last compiled " \
              "there, for your own Ruby). Take it from git or a gem server, so Fledge can compile it for the runtime's Ruby."
          end
          return nil
        end

        raise Error, "#{@lockfile_name} takes #{spec.name} from #{folder}, outside the project, and Fledge ships only what is " \
          "inside #{@root}. Move it into the project, or take it from a gem server."
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

      # The folder inside the project that +spec+ comes from, or +nil+ when
      # it is not a path gem in the project.
      def own_folder(spec)
        source = spec.source
        return nil unless source.is_a?(Bundler::Source::Path)

        folder = File.expand_path(source.path.to_s, @root)
        folder if inside_project?(folder)
      end

      private def inside_project?(folder)
        folder == @root || folder.start_with?("#{@root}/")
      end
    end
  end
end
