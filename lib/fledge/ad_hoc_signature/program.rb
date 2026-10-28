# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"

module Fledge
  class AdHocSignature
    # A thin 64-bit Mach-O program that already has a signature, read for
    # what signing it again changes: where its code ends and its old
    # signature begins, its +LC_CODE_SIGNATURE+ command, and its +__TEXT+
    # and +__LINKEDIT+ segments (Apple's mach-o/loader.h). Raises
    # Fledge::Error for any other file.
    class Program # :nodoc:
      def initialize(bytes)
        @bytes = bytes
        raise Error, "is not a 64-bit Mach-O program; Fledge signs only those" unless u32(@bytes, 0) == MAGIC_64

        commands = load_commands
        @signature = commands.fetch(LC_CODE_SIGNATURE) { raise Error, "has no code signature to replace" }.first
        @text = segment(commands, "__TEXT")
        @linkedit = segment(commands, "__LINKEDIT")
        raise Error, "has a code signature that is not at the end of __LINKEDIT" unless limit + u32(@bytes, @signature + 12) <= @bytes.bytesize
      end

      # Where the program's code ends and its old signature begins.
      def limit
        u32(@bytes, @signature + 8)
      end

      # The program's code, with its +LC_CODE_SIGNATURE+ and +__LINKEDIT+
      # resized for a signature of +size+ bytes after it, and its +__TEXT+
      # segment's file offset and size as that code says.
      def resized(size)
        code = @bytes.byteslice(0, limit).to_s
        code.bytesplice(@signature + 12, 4, [size].pack("V"))
        linkedit_size = limit + size - u64(code, @linkedit + 40)
        code.bytesplice(@linkedit + 32, 8, [align(linkedit_size, SEGMENT_ALIGNMENT)].pack("Q<"))
        code.bytesplice(@linkedit + 48, 8, [linkedit_size].pack("Q<"))
        [code, u64(code, @text + 40), u64(code, @text + 48)]
      end

      # The load commands by command, each the offsets of those with that
      # command.
      private def load_commands
        at = 32
        commands = Hash.new { |hash, key| hash[key] = [] } # : Hash[Integer, Array[Integer]]
        u32(@bytes, 16).times do
          commands[u32(@bytes, at)] << at
          at += u32(@bytes, at + 4)
        end
        commands
      end

      private def segment(commands, name)
        commands.fetch(LC_SEGMENT_64, []).find { |at| @bytes.byteslice(at + 8, 16).to_s.delete("\0") == name } or
          raise Error, "has no #{name} segment"
      end

      private def u32(bytes, at)
        bytes.byteslice(at, 4).to_s.unpack1("V").to_i
      end

      private def u64(bytes, at)
        bytes.byteslice(at, 8).to_s.unpack1("Q<").to_i
      end

      private def align(value, alignment)
        ((value + alignment - 1) / alignment) * alignment
      end
    end
  end
end
