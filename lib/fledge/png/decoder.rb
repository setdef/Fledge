# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class Png
    # Turns a PNG's inflated image data into 8-bit RGBA: undoes each row's
    # filter, pass by pass for an interlaced image, and has Pixels expand
    # each row's samples.
    class Decoder # :nodoc:
      def initialize(width:, height:, depth:, color:, interlace:, chunks:)
        @width = width
        @height = height
        @depth = depth
        @interlace = interlace
        @channels = CHANNELS.fetch(color)
        palette = chunk(chunks, "PLTE")
        raise Error, "is a palette PNG with no PLTE chunk" if color == 3 && palette.nil?

        @pixels = Pixels.new(depth:, color:, palette:, transparency: chunk(chunks, "tRNS"))
      end

      def decode(raw)
        pixels = @interlace.zero? ? decode_rows(raw) : decode_passes(raw)
        Png.new(width: @width, height: @height, pixels:)
      end

      # The pixels of a PNG that is not interlaced, row after row.
      private def decode_rows(raw)
        rows = [] # : Array[String]
        each_line(raw, 0, @width, @height) { |line, _| rows << @pixels.row(line, @width) }
        rows.join
      end

      # The pixels of an interlaced PNG, each of Adam7's seven passes
      # placed where its pixels go.
      private def decode_passes(raw)
        out = "\0".b * (@width * @height * 4)
        at = 0
        ADAM7.each do |x0, y0, dx, dy|
          columns = (@width - x0 + dx - 1) / dx
          rows = (@height - y0 + dy - 1) / dy
          next if columns <= 0 || rows <= 0

          at = each_line(raw, at, columns, rows) do |line, row|
            pixels = @pixels.row(line, columns)
            columns.times do |column|
              out.bytesplice((((y0 + (row * dy)) * @width) + x0 + (column * dx)) * 4, 4, pixels, column * 4, 4)
            end
          end
        end
        out
      end

      private def chunk(chunks, type)
        chunks.find { |name, _| name == type }&.last
      end

      # Unfilters each of the +rows+ lines of +columns+ pixels that start
      # at +at+ in +raw+, yields each with its row, and returns where the
      # next pass starts.
      private def each_line(raw, at, columns, rows)
        stride = ((columns * @channels * @depth) + 7) / 8
        step = [(@channels * @depth) / 8, 1].max
        previous = Array.new(stride, 0)
        rows.times do |row|
          filter = raw.getbyte(at)
          line = raw.byteslice(at + 1, stride).to_s.unpack("C*") #: Array[Integer]
          raise Error, "is a damaged PNG: its image data ends early" if filter.nil? || line.size < stride

          Filter.undo(filter, line, previous, step)
          yield line, row
          previous = line
          at += stride + 1
        end
        at
      end
    end
  end
end
