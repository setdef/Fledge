# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class Png
    # Turns an unfiltered line of a PNG's samples into 8-bit RGBA pixels,
    # through the palette and transparency the PNG gives, at whatever bit
    # depth and color type it has.
    class Pixels # :nodoc:
      def initialize(depth:, color:, palette:, transparency:)
        @depth = depth
        @color = color
        @channels = CHANNELS.fetch(color)
        @palette = palette
        @transparency = transparency
      end

      # An unfiltered +line+ of +columns+ pixels as 8-bit RGBA, by the
      # quickest way its color type allows: most icons are RGBA, RGB, or a
      # palette, at 8 bits.
      def row(line, columns)
        if @depth == 8 && @transparency.nil? && @color == 6
          line.pack("C*")
        elsif @depth == 8 && @transparency.nil? && @color == 2
          line.pack("C*").unpack("a3" * columns).join("\xFF".b) << "\xFF".b
        elsif @depth == 8 && @color == 3
          table = palette_table
          line.first(columns).map { |index| table[index] || palette_color(index) }.join
        else
          samples(line, columns).map { |sample| rgba(sample).pack("C4") }.join
        end
      end

      # Each palette entry as four RGBA bytes.
      private def palette_table
        @palette_table ||= Array.new(@palette.to_s.bytesize / 3) { |index| palette_color(index).pack("C4") }
      end

      # The samples of each pixel in an unfiltered +line+, as an Array per
      # pixel of integers at the PNG's own depth.
      private def samples(line, columns)
        if @depth == 8
          line.each_slice(@channels).first(columns)
        elsif @depth == 16
          line.each_slice(2).map { |high, low| (high.to_i << 8) | low.to_i }.each_slice(@channels).first(columns)
        else
          per_byte = 8 / @depth
          mask = (1 << @depth) - 1
          values = line.flat_map { |byte| Array.new(per_byte) { |k| (byte >> (8 - (@depth * (k + 1)))) & mask } }
          values.first(columns).map { |value| [value] }
        end
      end

      # One pixel's samples as 8-bit RGBA.
      private def rgba(sample)
        return palette_color(sample[0].to_i) if @color == 3

        alpha = transparent?(sample) ? 0 : 255
        case @color
        when 0 then gray(scale(sample[0]), alpha)
        when 2 then [scale(sample[0]), scale(sample[1]), scale(sample[2]), alpha]
        when 4 then gray(scale(sample[0]), scale(sample[1]))
        else [scale(sample[0]), scale(sample[1]), scale(sample[2]), scale(sample[3])]
        end
      end

      private def gray(level, alpha)
        [level, level, level, alpha]
      end

      # A sample at the PNG's depth as 8 bits, as the PNG specification's
      # section 13.12 scales one: the nearest 8-bit value.
      private def scale(value)
        value = value.to_i
        return value if @depth == 8
        return ((value * 255) + 32_767) / 65_535 if @depth == 16

        (value * 255) / ((1 << @depth) - 1)
      end

      # Whether a grayscale or RGB pixel is the one color +tRNS+ makes
      # transparent.
      private def transparent?(sample)
        transparency = @transparency
        return false if transparency.nil? || ![0, 2].include?(@color)

        transparency.unpack("n*").first(sample.size) == sample
      end

      private def palette_color(index)
        palette = @palette.to_s
        raise Error, "is a damaged PNG: a pixel names color #{index}, past its palette's end" if (index * 3) + 3 > palette.bytesize

        red, green, blue = palette.byteslice(index * 3, 3).to_s.unpack("C3")
        alpha = @transparency&.getbyte(index) || 255
        [red.to_i, green.to_i, blue.to_i, alpha]
      end
    end
  end
end
