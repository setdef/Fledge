# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class Binary
    # What <tt>objdump -p</tt> prints, GNU's and LLVM's alike, which
    # print ELF's dynamic section and version references in one form (LLVM
    # matches GNU's): a header line per file, "FILE: file format
    # elf64-x86-64", then for ELF a <tt>NEEDED</tt> line per library and,
    # under "Version References:", a line per symbol version, and for
    # Mach-O each load command as <tt>otool -l</tt> prints it (LLVM's
    # objdump is otool's own code, llvm-otool).
    module Objdump # :nodoc:
      # What to run the tool with before the files.
      ARGUMENTS = ["-p"].freeze

      # A file's header line, and a universal Mach-O file's for each of
      # its architectures.
      HEADER = /\A(.+?)(?: \(architecture [^)]+\))?:\s+file format (.+?)\s*\z/

      # The load commands that name a dylib the loader must find
      # (Apple's mach-o/loader.h).
      DYLIB_COMMANDS = %w[LC_LOAD_DYLIB LC_LOAD_WEAK_DYLIB LC_REEXPORT_DYLIB LC_LAZY_LOAD_DYLIB LC_LOAD_UPWARD_DYLIB].freeze

      # The options Fledge::Binary::Readers runs the tool with.
      def self.arguments
        ARGUMENTS
      end

      # What the tool printed for each of +paths+ it read, by path.
      def self.sections(output, paths)
        known = paths.to_h { |path| [path, true] }
        sections = {} # : Hash[String, String]
        current = nil # : String?
        output.each_line do |line|
          found = HEADER.match(line.chomp)
          current = found[1].to_s if found && known.key?(found[1].to_s)
          sections[current] = "#{sections[current]}#{line}" if current
        end
        sections
      end

      # Whether +error+, what the tool wrote to its standard error, says
      # it did not recognize the file at +path+: LLVM's "error: 'PATH':",
      # or GNU's "PATH: file format not recognized".
      def self.rejected?(error, path)
        error.include?("'#{path}'") || error.include?("#{path}: ")
      end

      # The Binary +section+ describes.
      def self.binary(section)
        format = section[/file format (\S+)/, 1].to_s
        if format.start_with?("mach-o")
          commands = section.split(/^Load command \d+\s*$/)
          Binary.new(format: :macho, needed: dylibs(commands), assemblies: [], macos_minimum: macos(commands), glibc_minimum: nil,
            subsystem: nil)
        else
          Binary.new(format: :elf, needed: section.scan(/^\s+NEEDED\s+(\S+)\s*$/).flatten.map(&:to_s).uniq, assemblies: [],
            macos_minimum: nil, glibc_minimum: glibc(section), subsystem: nil)
        end
      end

      # The dylibs the load +commands+ name, once each.
      def self.dylibs(commands)
        commands.filter_map do |command|
          command[/^\s*name (.+?) \(offset \d+\)\s*$/, 1] if DYLIB_COMMANDS.include?(command[/^\s*cmd (\S+)\s*$/, 1])
        end.uniq
      end

      # The newest macOS the load +commands+ say the file runs on: an
      # LC_BUILD_VERSION's minos for platform macos, or an older
      # LC_VERSION_MIN_MACOSX's version.
      def self.macos(commands)
        versions = commands.filter_map do |command|
          case command[/^\s*cmd (\S+)\s*$/, 1]
          when "LC_BUILD_VERSION" then command[/^\s*minos (\S+)\s*$/, 1] if command[/^\s*platform (\S+)\s*$/, 1] == "macos"
          when "LC_VERSION_MIN_MACOSX" then command[/^\s*version (\S+)\s*$/, 1]
          end
        end
        versions.map { |version| major_minor(version) }.max_by { |version| Gem::Version.new(version) }
      end

      # The newest <tt>GLIBC_X.Y</tt> among the file's version
      # references, as X.Y.
      def self.glibc(section)
        references = section[/^Version References:\s*\n(.*?)(?:\n\s*\n|\z)/m, 1].to_s
        references.scan(/\sGLIBC_(\d+(?:\.\d+)+)\s*$/).flatten.map(&:to_s).max_by { |version| Gem::Version.new(version) }
      end

      # +version+ as MAJOR.MINOR.
      def self.major_minor(version)
        major, minor = version.split(".")
        "#{major}.#{minor || 0}"
      end
    end
  end
end
