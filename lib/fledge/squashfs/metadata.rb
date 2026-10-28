# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"

module Fledge
  class Squashfs
    # A metadata stream: records written one after another, in blocks of
    # METADATA bytes compressed one by one. #position says where the next
    # record goes, as a block's on-disk offset and an offset into it.
    class Metadata # :nodoc:
      def initialize
        @disk = "".b
        @pending = "".b
      end

      def position
        [@disk.bytesize, @pending.bytesize]
      end

      def reference
        block, offset = position
        (block << 16) | offset
      end

      def <<(bytes)
        @pending << bytes
        flush(@pending.slice!(0, METADATA).to_s) while @pending.bytesize >= METADATA
        self
      end

      def bytes
        flush(@pending.slice!(0..).to_s) unless @pending.empty?
        @disk
      end

      private def flush(block)
        compressed = Zlib::Deflate.deflate(block, Zlib::BEST_COMPRESSION)
        if compressed.bytesize < block.bytesize
          @disk << [compressed.bytesize].pack("v") << compressed
        else
          @disk << [block.bytesize | METADATA_UNCOMPRESSED].pack("v") << block
        end
      end
    end
  end
end
