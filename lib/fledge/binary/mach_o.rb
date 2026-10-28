# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from tasks/license_audit/binary.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
module Fledge
  class Binary
    # A Mach-O file's load commands, read for the dylibs and search paths
    # it names (what <tt>otool -L</tt> and <tt>otool -l</tt> print) and
    # the oldest macOS it says it runs on. A universal (fat) file reads as
    # its first architecture's slice.
    class MachO < Reader # :nodoc:
      # The Mach-O load commands that name a dylib: LC_LOAD_DYLIB,
      # LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LAZY_LOAD_DYLIB, and
      # LC_LOAD_UPWARD_DYLIB.
      LC_DYLIBS = [0xC, 0x80000018, 0x8000001F, 0x20, 0x80000023].freeze

      # The Mach-O load command that adds a search path.
      LC_RPATH = 0x8000001C

      # The Mach-O load command that says which macOS a file was built for,
      # and so the oldest it loads on, in its third word, minos (Apple's
      # mach-o/loader.h).
      LC_BUILD_VERSION = 0x32

      # The older load command that says the same, in its second word.
      LC_VERSION_MIN_MACOSX = 0x24

      # Where, in each command that says the oldest macOS, its version is.
      MINIMUM_AT = { LC_BUILD_VERSION => 12, LC_VERSION_MIN_MACOSX => 8 }.freeze

      # Whether +bytes+ begin a universal file, whose header counts its
      # architectures where a Java class file, which shares its magic,
      # has its version (always 45 or more).
      def self.fat?(bytes)
        bytes.start_with?(FAT_MAGIC) && bytes.byteslice(4, 4).to_s.unpack1("N").to_i < 32
      end

      def initialize(bytes)
        super
        @base = MachO.fat?(bytes) ? number(16, 4, "N") : 0
      end

      # Whether the bytes (or their first slice) are a Mach-O file.
      def macho?
        MACHO_MAGICS.include?(@bytes.byteslice(@base, 4))
      end

      # The dylibs the load commands name, and the search paths they add.
      def links
        needed = [] # : Array[String]
        rpaths = [] # : Array[String]
        each_command do |command, offset|
          if LC_DYLIBS.include?(command)
            needed << command_string(offset)
          elsif command == LC_RPATH
            rpaths << command_string(offset)
          end
        end
        [needed, rpaths]
      end

      # The oldest macOS the first command that names one says, as X.Y.
      def minimum
        each_command do |command, offset|
          at = MINIMUM_AT[command]
          return version_text(number(offset + at, 4, "L<")) if at
        end
        nil
      end

      # Yields each load command's type and offset.
      private def each_command
        offset = @base + ((@bytes.byteslice(@base, 4) == MACHO_MAGICS.first) ? 32 : 28)
        number(@base + 16, 4, "L<").times do
          yield number(offset, 4, "L<"), offset
          offset += number(offset + 4, 4, "L<")
        end
      end

      # The string a load command at +offset+ holds, which its third word
      # says where it begins.
      private def command_string(offset)
        c_string(offset + number(offset + 8, 4, "L<"))
      end

      # A Mach-O version, X.Y.Z in nibbles xxxx.yy.zz, as X.Y.
      private def version_text(packed)
        "#{packed >> 16}.#{(packed >> 8) & 0xFF}"
      end
    end
  end
end
