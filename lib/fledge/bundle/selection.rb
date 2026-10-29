# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"

module Fledge
  class Bundle
    # The gems a lockfile locks that one platform's app ships: each gem the
    # Gemfile's dependencies reach there, outside WITHOUT's groups and the
    # gems the Gemfile limits to other platforms, each the build Bundler
    # would choose on that platform's runtime (Bundler::MatchPlatform).
    class Selection # :nodoc:
      # A selection from +definition+'s lockfile, named +lockfile_name+,
      # for +platform+, whose runtime is Ruby +ruby_version+ on the RubyGems
      # platform +target+.
      def initialize(definition, lockfile_name:, platform:, ruby_version:, target:)
        @definition = definition
        @lockfile_name = lockfile_name
        @platform = platform
        @ruby_version = ruby_version
        @target = target
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

      private def best(lookup, name, force_ruby)
        candidates = lookup[name] or raise Error, "#{@lockfile_name} locks no #{name}. Run bundle lock, then build again."
        force_ruby ||= @platform.force_ruby_platform?
        Bundler::MatchPlatform.select_best_platform_match(candidates, @target, force_ruby:).first or
          raise Error, "#{@lockfile_name} locks no build of #{name} for #{@platform}, only for " \
            "#{candidates.map { |spec| spec.platform.to_s }.sort.join(', ')}. If #{name} has one, run bundle lock " \
            "--add-platform #{@platform.lockfile_names.first}, then build again."
      end

      # Whether the dependency is one Bundler sets up on the platform, outside
      # WITHOUT's groups.
      private def ships?(dependency)
        return false if (dependency.groups - WITHOUT).empty?
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
