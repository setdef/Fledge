# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../binary"

module Fledge
  class NativeBuild
    # What a compiled file needs of the system it runs on beyond what the
    # runtime needs: a newer macOS, or a newer glibc, which a compiler
    # targets when it builds on a newer computer. A file for another
    # processor than the platform's (Binary#for?), which a build may leave
    # beside its own as a gem for every platform carries one for each,
    # never loads in the app, so its needs are nothing.
    #
    # On macOS that is a problem: Fledge compiles for the runtime's
    # oldest macOS (MACOSX_DEPLOYMENT_TARGET), so a file that needs a
    # newer one was built against that on purpose, and the app would
    # stop on the systems it promises. On Linux it is a warning: a file
    # needs the glibc it was compiled with or a newer one, as glibc's
    # symbol versions make it, so the app needs this computer's glibc,
    # which a Linux with an older one would not have; the app's
    # <tt>.deb</tt> says so (Fledge::Deb), and building on an older
    # system lowers it (doc/contributors/design/gems.md, "The glibc a
    # compiled gem needs").
    module Floors # :nodoc:
      COMPILED_ADVICE = "Fledge compiled it on this computer, and a compiled file needs the glibc it was compiled with or a newer one: " \
        "build the app on a Linux with an older glibc, such as AlmaLinux 8, to lower that."
      private_constant :COMPILED_ADVICE

      PRECOMPILED_ADVICE = "The gem arrived compiled, and a compiled file needs the glibc it was compiled with or a newer one: use a " \
        "build of the gem for an older glibc if it has one, or have Bundler compile it from its source, with " \
        "force_ruby_platform: true on its line in the Gemfile, on a Linux with an older glibc, such as AlmaLinux 8."
      private_constant :PRECOMPILED_ADVICE

      # The problems of +gem+'s compiled +entries+ on +platform+, one per
      # file for its processor that needs a newer macOS than the
      # platform's oldest, as +readers+ (Fledge::Binary::Readers) read
      # them.
      def self.problems(gem, entries, platform, readers: Binary::Readers.local(platform.os))
        floor = platform.macos_minimum
        return [] unless floor

        needing(:macho, entries, platform, readers, &:macos_minimum).filter_map do |path, found|
          next unless newer?(found, floor)

          "#{gem}'s #{path} needs macOS #{found}, and apps for #{platform} run on macOS #{floor} and later. Compile it with " \
            "MACOSX_DEPLOYMENT_TARGET=#{floor}, which Fledge sets, so check its extconf.rb does not override it."
        end
      end

      # The warnings about +gem+'s compiled +entries+ on +platform+, one
      # per file for its processor that needs a newer glibc than the
      # platform's oldest, which the app then needs. A file whose bytes
      # an earlier one has is one file to the app (a build installs an
      # extension into the gem's require path, and RubyGems keeps a copy
      # in the extensions folder: Fledge::CompiledGem), so it warns once,
      # at the first path. For +precompiled+ files, which a gem's authors
      # compiled and Fledge did not, the warning says so and what lowers
      # the need: a build of the gem against an older glibc.
      def self.warnings(gem, entries, platform, precompiled: false, readers: Binary::Readers.local(platform.os))
        floor = platform.glibc_minimum
        return [] unless floor

        entries = entries.uniq { |entry| (entry.type == :file) ? entry.content.to_s : entry.path }
        needing(:elf, entries, platform, readers, &:glibc_minimum).filter_map do |path, found|
          next unless newer?(found, floor)

          "#{gem}'s #{path} needs glibc #{found}, so the app for #{platform} runs only on Linux with glibc #{found} or newer, " \
            "where Fledge's runtime runs on glibc #{floor} and later. " + (precompiled ? PRECOMPILED_ADVICE : COMPILED_ADVICE)
        end
      end

      # The glibc an app for +platform+ needs whose own files, beside its
      # runtime's, are +entries+: the newest any of their files for its
      # processor needs, as auditwheel reads a wheel's
      # (Binary#glibc_minimum), and at least +floor+, the runtime's
      # (Platform#glibc_minimum), since the runtime's build holds its
      # files to that. +nil+ for a platform without glibc. Only +entries+
      # that are ELF files are read, so for an app with none this reads
      # nothing and needs no tool.
      def self.glibc(entries, platform, floor: platform.glibc_minimum, readers: Binary::Readers.local(platform.os))
        return nil unless floor

        needed = needing(:elf, entries, platform, readers, &:glibc_minimum).map(&:last)
        [floor, *needed].max_by { |version| Gem::Version.new(version) }
      end

      # Each of +entries+ of +format+ for the platform's processor, by
      # path, with the version of the system it needs that the block
      # reads from its Binary, when it names one.
      private_class_method def self.needing(format, entries, platform, readers)
        files = entries.filter_map do |entry|
          content = entry.content.to_s
          [entry.path, content] if entry.type == :file && Binary.format_of(content.byteslice(0, 8).to_s) == format
        end
        Binary.parse(files.to_h, readers:).filter_map do |path, binary|
          found = yield(binary) if binary.for?(platform.cpu)
          [path, found] if found
        end
      end

      private_class_method def self.newer?(found, floor)
        Gem::Version.new(found) > Gem::Version.new(floor)
      end
    end
  end
end
