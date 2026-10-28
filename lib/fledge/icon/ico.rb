# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../png"

module Fledge
  class Icon
    # Windows' icon format, as Microsoft's "Icons" in the Win32
    # documentation describes it: the bitmap of each image an icon
    # resource holds, and the <tt>.ico</tt> file that holds them all.
    module Ico # :nodoc:
      # +image+ as the bitmap of an icon image: a BITMAPINFOHEADER whose
      # height counts the AND mask's rows too, the pixels as BGRA from the
      # bottom row up, and an AND mask of zeros, since the alpha channel
      # says what is transparent.
      def self.bitmap(image)
        side = image.width
        header = [40, side, side * 2, 1, 32, 0, 0, 0, 0, 0, 0].pack("Vl<l<vvVVl<l<VV")
        stride = side * 4
        rows = Array.new(side) { |row| bgra(image.pixels.byteslice((side - 1 - row) * stride, stride).to_s) }
        mask_stride = ((side + 31) / 32) * 4
        header + rows.join + ("\0".b * (mask_stride * side))
      end

      # An <tt>.ico</tt> of +images+, each a size and its image: an
      # ICONDIR, an ICONDIRENTRY for each image, and the images after them.
      def self.file(images)
        offset = 6 + (16 * images.size)
        entries = images.map do |size, data|
          entry = [size % 256, size % 256, 0, 0, 1, 32, data.bytesize, offset].pack("CCCCvvVV")
          offset += data.bytesize
          entry
        end
        [0, 1, images.size].pack("vvv") + entries.join + images.map(&:last).join
      end

      # A row of RGBA pixels as BGRA.
      private_class_method def self.bgra(row)
        row.unpack("C*").each_slice(4).map { |red, green, blue, alpha| [blue, green, red, alpha].pack("C4") }.join
      end
    end
  end
end
