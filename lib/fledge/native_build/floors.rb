# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../binary"

module Fledge
  class NativeBuild
    # Why a compiled file would not load on the oldest system the runtime
    # runs on: a newer macOS than it, or a newer glibc, which a compiler
    # targets when it builds on a newer computer.
    module Floors # :nodoc:
      # The problems of +gem+'s compiled +entries+ on +platform+, one per
      # file that needs a newer system than the platform's oldest.
      def self.problems(gem, entries, platform)
        entries.filter_map do |entry|
          bytes = (entry.type == :file) ? entry.content.to_s : ""
          macos(gem, entry, bytes, platform) || glibc(gem, entry, bytes, platform)
        end
      end

      private_class_method def self.macos(gem, entry, bytes, platform)
        floor = platform.macos_minimum or return nil
        found = Binary.macos_minimum(bytes)
        return nil unless found && newer?(found, floor)

        "#{needs(gem, entry, platform, 'macOS', found, floor)} Compile it with MACOSX_DEPLOYMENT_TARGET=#{floor}, which " \
          "Fledge sets, so check its extconf.rb does not override it."
      end

      private_class_method def self.glibc(gem, entry, bytes, platform)
        floor = platform.glibc_minimum or return nil
        found = Binary.glibc_minimum(bytes)
        return nil unless found && newer?(found, floor)

        "#{needs(gem, entry, platform, 'glibc', found, floor)} Build on a Linux with glibc #{floor}, such as Ubuntu 24.04."
      end

      private_class_method def self.needs(gem, entry, platform, system, found, floor)
        "#{gem}'s #{entry.path} needs #{system} #{found}, and apps for #{platform} run on #{system} #{floor} and later."
      end

      private_class_method def self.newer?(found, floor)
        Gem::Version.new(found) > Gem::Version.new(floor)
      end
    end
  end
end
