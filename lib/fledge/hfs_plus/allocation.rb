# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class HfsPlus
    # The allocation file: a bit for each block of the volume, set for
    # each block in use, sized to fit the volume and itself.
    module Allocation # :nodoc:
      # The volume's size in blocks and the bitmap's, for a bitmap that
      # begins at +start+: the bitmap holds a bit for each block, itself
      # included, and the last block holds the second volume header.
      def self.layout(start)
        bitmap_blocks = 1
        loop do
          total = start + bitmap_blocks + 1
          needed = (((total + 7) / 8) + BLOCK - 1) / BLOCK
          return [total, bitmap_blocks] if needed <= bitmap_blocks

          bitmap_blocks = needed
        end
      end

      # Every block in use: the volume holds what it was given and no more.
      def self.bitmap(total, blocks)
        bits = (0xFF.chr * (total / 8)) + ((total % 8).zero? ? "".b : [(0xFF << (8 - (total % 8))) & 0xFF].pack("C"))
        bits + ("\0".b * ((blocks * BLOCK) - bits.bytesize))
      end
    end
  end
end
