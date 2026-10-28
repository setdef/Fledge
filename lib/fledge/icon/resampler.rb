# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../png"

module Fledge
  class Icon
    # Shrinks an image with an area-averaging filter that weighs each
    # pixel's color by its alpha, so a transparent edge does not darken.
    module Resampler # :nodoc:
      # +image+ shrunk to +size+ pixels a side: each new pixel the average
      # of the area of the old ones it covers, each weighed by its alpha,
      # so the color of a pixel that is nearly transparent counts for
      # little.
      def self.shrink(image, size)
        return halve(image) if image.width == size * 2

        columns = weights(image.width, size)
        rows = weights(image.height, size)
        source = image.pixels.unpack("C*") #: Array[Integer]
        width = image.width
        pixels = rows.flat_map do |row_weights|
          columns.flat_map { |column_weights| average(source, width, row_weights, column_weights) }
        end
        Png.new(width: size, height: size, pixels: pixels.pack("C*"))
      end

      # +image+ at half its size, each new pixel the alpha-weighed average
      # of a square of four: the common case of #shrink, which an icon's
      # sizes mostly are, in integer arithmetic.
      private_class_method def self.halve(image)
        side = image.width / 2
        stride = image.width * 4
        rows = Array.new(side) do |y|
          top = image.pixels.byteslice(y * 2 * stride, stride).to_s.unpack("C*") #: Array[Integer]
          bottom = image.pixels.byteslice(((y * 2) + 1) * stride, stride).to_s.unpack("C*") #: Array[Integer]
          row = Array.new(side * 4, 0)
          x = 0
          while x < side
            blend(row, x, top, bottom)
            x += 1
          end
          row.pack("C*")
        end
        Png.new(width: side, height: side, pixels: rows.join)
      end

      # Sets pixel +x+ of +row+ to the alpha-weighed average of the square
      # of four pixels it covers in the rows +top+ and +bottom+, or leaves
      # it transparent black when all four are transparent. This runs once
      # for every pixel of a halved image, so it is written as plainly as
      # Ruby runs fastest.
      private_class_method def self.blend(row, x, top, bottom)
        at = x * 8
        a1 = top[at + 3].to_i
        a2 = top[at + 7].to_i
        a3 = bottom[at + 3].to_i
        a4 = bottom[at + 7].to_i
        alpha = a1 + a2 + a3 + a4
        return if alpha.zero?

        3.times do |channel|
          sum = (top[at + channel].to_i * a1) + (top[at + 4 + channel].to_i * a2) +
            (bottom[at + channel].to_i * a3) + (bottom[at + 4 + channel].to_i * a4)
          row[(x * 4) + channel] = (sum + (alpha / 2)) / alpha
        end
        row[(x * 4) + 3] = (alpha + 2) / 4
      end

      # For each of +to+ cells across +from+ pixels, the pixels it covers and
      # how much of each.
      private_class_method def self.weights(from, to)
        scale = from.fdiv(to)
        Array.new(to) do |cell|
          start = cell * scale
          finish = start + scale
          ((start.floor)...(finish.ceil)).filter_map do |pixel|
            covered = [finish, pixel + 1.0].min - [start, pixel.to_f].max
            [pixel, covered] if covered.positive?
          end
        end
      end

      # One new pixel: the source pixels the cell covers, by their
      # +row_weights+ and +column_weights+, each color weighed by its
      # alpha, and the alpha by the area.
      private_class_method def self.average(source, width, row_weights, column_weights)
        red = green = blue = alpha = area = 0.0
        row_weights.each do |y, row_weight|
          column_weights.each do |x, column_weight|
            at = ((y * width) + x) * 4
            weight = row_weight * column_weight
            opacity = source[at + 3].to_i * weight
            red += source[at].to_i * opacity
            green += source[at + 1].to_i * opacity
            blue += source[at + 2].to_i * opacity
            alpha += opacity
            area += weight
          end
        end
        return [0, 0, 0, 0] if alpha.zero?

        [(red / alpha).round, (green / alpha).round, (blue / alpha).round, (alpha / area).round]
      end
    end
  end
end
