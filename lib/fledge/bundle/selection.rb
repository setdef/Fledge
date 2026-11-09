# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../error"

module Fledge
  class Bundle
    # The gems a lockfile locks that one platform's app ships: each gem the
    # Gemfile's dependencies reach there, in the groups the app sets up and
    # not the gems the Gemfile limits to other platforms, each the build Bundler
    # would choose on that platform's runtime (Bundler::MatchPlatform).
    class Selection # :nodoc:
      # A selection from +definition+'s lockfile, named +lockfile_name+,
      # for +platform+, whose runtime is Ruby +ruby_version+ on the RubyGems
      # platform +target+, setting up +groups+ (symbols). +runs+ answers
      # whether a locked specification's +required_ruby_version+ admits
      # the runtime's Ruby, and is asked only when a gem has a build to
      # fall back to.
      def initialize(definition, lockfile_name:, platform:, ruby_version:, target:, groups:, runs:)
        @definition = definition
        @lockfile_name = lockfile_name
        @platform = platform
        @ruby_version = ruby_version
        @target = target
        @groups = groups
        @runs = runs
      end

      # The locked specifications the app's dependencies reach on the
      # platform, each the one Bundler would choose there.
      def specs
        lookup = @definition.locked_gems.specs.group_by(&:name)
        queue = @definition.dependencies.select { |dependency| ships?(dependency) }
          .map { |dependency| [dependency.name, dependency.force_ruby_platform || false] } # : Array[[String, bool]]
        seen = {} # : Hash[String, bool]
        specs = [] # : Array[Bundler::LazySpecification]
        while (name, force_ruby = queue.shift)
          next if seen[name] || name == "bundler"

          seen[name] = true
          spec = best(lookup, name, force_ruby)
          specs << spec
          spec.dependencies.each { |dependency| queue << [dependency.name, false] unless dependency.type == :development }
        end
        specs
      end

      # The build of +name+ Bundler would set up: the best match for the
      # target's platform, or, when its +required_ruby_version+ excludes
      # the runtime's Ruby (as sqlite3 2.10.2's precompiled builds exclude
      # Ruby 4.1), the gem's source build, which Fledge compiles. With no
      # build that admits the runtime's Ruby, the best match stays, and
      # Fledge::AppGems names it, as a frozen Bundler would fail on it.
      #
      # A frozen Bundler 4.0.20 materializes a locked build against its
      # source's specifications, which carry +required_ruby_version+
      # (Bundler::MatchMetadata#matches_current_ruby?,
      # <tt>bundler/match_metadata.rb</tt>, lines 9 to 11), and skips one
      # that does not match: Bundler::LazySpecification#choose_compatible
      # (<tt>bundler/lazy_specification.rb</tt>, lines 236 to 250) finds
      # none, so #materialize_for_installation (lines 137 to 152) tries
      # each of #candidate_platforms (lines 203 to 206), the local
      # platform and then +ruby+, "since it requires compilation, but
      # works when precompiled gems are incompatible", and with none
      # compatible keeps the locked platform's build
      # (#frozen_bundle_fallback, lines 211 to 216). The lockfile does not
      # record +required_ruby_version+, so +runs+ reads it from the build's
      # <tt>.gem</tt>.
      #--
      # SPDX-SnippetBegin
      # SPDX-License-Identifier: MIT
      # SPDX-SnippetCopyrightText: 2010-2019 André Arko, 2009 Engine Yard
      # SPDX-SnippetComment: Bundler::LazySpecification#find_compatible_platform_spec,
      #   #candidate_platforms, and #frozen_bundle_fallback, adapted from
      #   bundler/lazy_specification.rb at Bundler 4.0.20 (lines 192 to 216),
      #   with the runtime's platform as Bundler's local one.
      #++
      private def best(lookup, name, force_ruby)
        candidates = lookup[name] or raise Error, "#{@lockfile_name} locks no #{name}. Run bundle lock, then build again."
        force_ruby ||= @platform.force_ruby_platform?
        builds = [@target, Gem::Platform::RUBY].uniq.map do |platform|
          Bundler::MatchPlatform.select_best_platform_match(candidates, platform, force_ruby:)
        end
        locked = builds.first.first or no_build(name, candidates)
        choices = builds.flatten.uniq
        return locked if choices.one?

        choices.find { |spec| @runs.call(spec) } || locked
      end
      #--
      # SPDX-SnippetEnd
      #++

      private def no_build(name, candidates)
        raise Error, "#{@lockfile_name} locks no build of #{name} for #{@platform}, only for " \
          "#{candidates.map { |spec| spec.platform.to_s }.sort.join(', ')}. If #{name} has one, run bundle lock " \
          "--add-platform #{@platform.lockfile_names.first}, then build again."
      end

      # Whether the dependency is one Bundler sets up on the platform, in
      # one of the groups the app sets up.
      private def ships?(dependency)
        return false if (dependency.groups & @groups).empty?
        return false unless dependency.should_include && dependency.current_env?

        dependency.platforms.empty? || dependency.platforms.any? { |name| on_platform?(name.to_s) }
      end

      # Whether a Gemfile's <tt>platforms:</tt> name holds on the platform,
      # as Bundler::CurrentRuby answers it on that platform's runtime, a
      # CRuby: +windows+ (and its old names +mswin+, +mingw+, and
      # +x64_mingw+) on Windows, +ruby+ and +mri+ everywhere else, never
      # +jruby+ or +truffleruby+, each with an optional Ruby version, such
      # as +mri_40+.
      private def on_platform?(name)
        base, digits = name.match(/\A(.+?)(?:_(\d+))?\z/)&.captures
        holds = case base
                when "windows", "mswin", "mswin64", "mingw", "x64_mingw" then @platform.windows?
                when "ruby", "mri" then !@platform.windows?
                else false
        end
        holds && (digits.nil? || @ruby_version.start_with?("#{digits.to_s.chars.join('.')}."))
      end
    end
  end
end
