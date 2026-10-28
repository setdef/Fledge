# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class Png
    # Undoes PNG's five filters (section 9.2), each on one line of bytes,
    # in place. These loops run once for every byte of an image, so they
    # are written as plainly as Ruby runs fastest.
    module Filter # :nodoc:
      # Undoes the filter of type +filter+ on +line+, whose line above is
      # +previous+ and whose pixels are +step+ bytes apart.
      def self.undo(filter, line, previous, step)
        case filter
        when 0 then nil
        when 1 then sub(line, step)
        when 2 then up(line, previous)
        when 3 then average(line, previous, step)
        when 4 then paeth(line, previous, step)
        else raise Error, "is a damaged PNG: a row has filter type #{filter}, which PNG does not define"
        end
      end

      # Each byte was the difference from the byte to its left.
      private_class_method def self.sub(line, step)
        size = line.size
        index = step
        while index < size
          line[index] = (line[index] + line[index - step]) & 0xFF
          index += 1
        end
      end

      # Each byte was the difference from the byte above it.
      private_class_method def self.up(line, previous)
        size = line.size
        index = 0
        while index < size
          line[index] = (line[index] + previous[index]) & 0xFF
          index += 1
        end
      end

      # Each byte was the difference from the mean of its left and upper
      # neighbors.
      private_class_method def self.average(line, previous, step)
        size = line.size
        index = 0
        while index < size
          line[index] = (line[index] + ((left(line, index, step) + previous[index]) >> 1)) & 0xFF
          index += 1
        end
      end

      # Each byte was the difference from whichever neighbor Paeth's
      # predictor chose.
      private_class_method def self.paeth(line, previous, step)
        size = line.size
        index = 0
        while index < size
          up_left = (index >= step) ? previous[index - step] : 0
          line[index] = (line[index] + predict(left(line, index, step), previous[index], up_left)) & 0xFF
          index += 1
        end
      end

      # The byte +step+ to the left of +index+, or 0 at the line's start.
      private_class_method def self.left(line, index, step)
        (index >= step) ? line[index - step] : 0
      end

      # Paeth's predictor: whichever of the left, upper, and upper-left
      # neighbors is nearest their linear estimate.
      private_class_method def self.predict(left, up, up_left)
        estimate = left + up - up_left
        to_left = (estimate - left).abs
        to_up = (estimate - up).abs
        to_up_left = (estimate - up_left).abs
        return left if to_left <= to_up && to_left <= to_up_left

        (to_up <= to_up_left) ? up : up_left
      end
    end
  end
end
