# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../binary"

module Fledge
  class NativeBuild
    # Why a compiled file would not load on the oldest system the runtime
    # runs on: a newer macOS than it, or a newer glibc, which a compiler
    # targets when it builds on a newer computer.
    module Floors # :nodoc:
      # The problems of +gem+'s compiled +entries+ on +platform+, one per
      # file that needs a newer system than the platform's oldest, as
      # +readers+ (Fledge::Binary::Readers) read them.
      def self.problems(gem, entries, platform, readers: Binary::Readers.local(platform.os))
        floors = { macho: platform.macos_minimum, elf: platform.glibc_minimum }.compact
        files = entries.filter_map do |entry|
          content = entry.content.to_s
          [entry.path, content] if entry.type == :file && floors.key?(Binary.format_of(content.byteslice(0, 8).to_s))
        end
        Binary.parse(files.to_h, readers:).filter_map do |path, binary|
          (binary.format == :macho) ? macos(gem, path, binary, platform) : glibc(gem, path, binary, platform)
        end
      end

      private_class_method def self.macos(gem, path, binary, platform)
        floor = platform.macos_minimum.to_s
        found = binary.macos_minimum
        return nil unless found && newer?(found, floor)

        "#{needs(gem, path, platform, 'macOS', found, floor)} Compile it with MACOSX_DEPLOYMENT_TARGET=#{floor}, which " \
          "Fledge sets, so check its extconf.rb does not override it."
      end

      private_class_method def self.glibc(gem, path, binary, platform)
        floor = platform.glibc_minimum.to_s
        found = binary.glibc_minimum
        return nil unless found && newer?(found, floor)

        "#{needs(gem, path, platform, 'glibc', found, floor)} Build on a Linux with glibc #{floor}, such as Ubuntu 24.04."
      end

      private_class_method def self.needs(gem, path, platform, system, found, floor)
        "#{gem}'s #{path} needs #{system} #{found}, and apps for #{platform} run on #{system} #{floor} and later."
      end

      private_class_method def self.newer?(found, floor)
        Gem::Version.new(found) > Gem::Version.new(floor)
      end
    end
  end
end
