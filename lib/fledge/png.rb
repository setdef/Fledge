# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"
require_relative "error"

module Fledge
  # A picture, read from or written to a PNG file.
  #
  # Your app's icon starts as one PNG, and each operating system wants it
  # in its own shapes: an <tt>.icns</tt> for macOS, icon resources inside a
  # Windows program, and PNGs of set sizes for Linux. Converting it takes
  # decoding the PNG, shrinking it, and encoding the results. Ruby's
  # standard library has zlib, which does PNG's compression, but nothing
  # that reads or writes the format around it, and an image library would
  # be the only gem Fledge needs, with a native extension, on every
  # computer that builds an app.
  #
  # This class reads every PNG the W3C's PNG specification (third
  # edition) defines: each color type and bit depth, palettes, the
  # transparency of +tRNS+, and Adam7 interlacing. It checks each chunk's
  # CRC, and holds the result as 8-bit RGBA, straight (not premultiplied)
  # alpha, one row after another. It writes 8-bit RGBA PNGs. It ignores
  # color profiles and gamma, as browsers do for an image with none, so an
  # icon looks as its PNG does in most viewers.
  #
  # Use it through Fledge::Icon.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   png = Fledge::Png.read(File.binread("icon.png"))
  #   png.width # => 1024
  #
  #   dot = Fledge::Png.new(width: 1, height: 1, pixels: "\xFF\x00\x00\xFF".b)
  #   File.binwrite("dot.png", dot.encode)
  #--
  # SPDX-SnippetEnd
  #++
  class Png < Data.define(:width, :height, :pixels)
    ##
    # :attr_reader: width
    # The width, in pixels.

    ##
    # :attr_reader: height
    # The height, in pixels.

    ##
    # :attr_reader: pixels
    # The pixels as a binary String: four bytes (red, green, blue, alpha)
    # for each, left to right, top to bottom.

    # The eight bytes every PNG begins with.
    SIGNATURE = "\x89PNG\r\n\x1A\n".b

    # The channels each color type has: grayscale, RGB, a palette index,
    # grayscale with alpha, and RGBA.
    CHANNELS = { 0 => 1, 2 => 3, 3 => 1, 4 => 2, 6 => 4 }.freeze

    # The bit depths each color type allows.
    DEPTHS = { 0 => [1, 2, 4, 8, 16], 2 => [8, 16], 3 => [1, 2, 4, 8], 4 => [8, 16], 6 => [8, 16] }.freeze

    # Adam7's seven passes: the column and row each starts at, and the
    # columns and rows it steps by.
    ADAM7 = [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]].freeze

    # The largest width or height read: a bound on the memory a damaged or
    # hostile file can ask for.
    MAX_SIDE = 16_384

    # Reads the PNG in +bytes+. Raises Fledge::Error, saying what is wrong,
    # for anything that is not a PNG this class can read.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Png.read(File.binread("icon.png")).height # => 1024
    #--
    # SPDX-SnippetEnd
    #++
    def self.read(bytes)
      bytes = bytes.b
      raise Error, "is not a PNG" unless bytes.start_with?(SIGNATURE)

      chunks = chunks_of(bytes)
      header = chunks.find { |type, _| type == "IHDR" } or raise Error, "is not a PNG: it has no IHDR chunk"
      width, height, depth, color, compression, filter, interlace = header.last.unpack("NNCCCCC").map(&:to_i)
      check_header(width.to_i, height.to_i, depth.to_i, color.to_i, [compression.to_i, filter.to_i, interlace.to_i])
      data = chunks.select { |type, _| type == "IDAT" }.map(&:last).join
      raw = inflate(data)
      Decoder.new(width: width.to_i, height: height.to_i, depth: depth.to_i, color: color.to_i, interlace: interlace.to_i, chunks:).decode(raw)
    end

    private_class_method def self.chunks_of(bytes) # :nodoc:
      chunks = [] # : Array[[String, String]]
      at = SIGNATURE.bytesize
      while at < bytes.bytesize
        length, type = bytes.byteslice(at, 8).to_s.unpack("Na4")
        length = length.to_i
        data = bytes.byteslice(at + 8, length).to_s
        crc = bytes.byteslice(at + 8 + length, 4).to_s
        raise Error, "is not a whole PNG: it ends inside a chunk" if data.bytesize < length || crc.bytesize < 4
        raise Error, "is a damaged PNG: its #{type} chunk fails its CRC" unless crc.unpack1("N") == Zlib.crc32(type.to_s + data)

        chunks << [type.to_s, data]
        at += 12 + length
        return chunks if type == "IEND"
      end
      raise Error, "is not a whole PNG: it has no IEND chunk"
    end

    private_class_method def self.check_header(width, height, depth, color, methods) # :nodoc:
      raise Error, "is a PNG of color type #{color}, which the PNG specification does not define" unless CHANNELS.key?(color)
      raise Error, "is a PNG of bit depth #{depth}, which its color type does not allow" unless DEPTHS.fetch(color).include?(depth)
      raise Error, "is a PNG with a compression, filter, or interlace method it does not define" unless methods[0..1] == [0, 0] && [0, 1].include?(methods[2])
      return if width.between?(1, MAX_SIDE) && height.between?(1, MAX_SIDE)

      raise Error, "is a PNG of #{width}x#{height} pixels; Fledge reads PNGs of 1 to #{MAX_SIDE} pixels a side"
    end

    private_class_method def self.inflate(data) # :nodoc:
      Zlib::Inflate.inflate(data)
    rescue Zlib::Error => e
      raise Error, "is a damaged PNG: its image data does not inflate (#{e.message})"
    end

    # The picture as an 8-bit RGBA PNG, each row unfiltered and the whole
    # compressed by zlib at its default level.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Png.new(width: 1, height: 1, pixels: "\0\0\0\0".b).encode.start_with?(Fledge::Png::SIGNATURE) # => true
    #--
    # SPDX-SnippetEnd
    #++
    def encode
      stride = width * 4
      rows = Array.new(height) { |row| "\0".b + pixels.byteslice(row * stride, stride).to_s }
      header = [width, height, 8, 6, 0, 0, 0].pack("NNCCCCC")
      SIGNATURE + chunk("IHDR", header) + chunk("IDAT", Zlib::Deflate.deflate(rows.join)) + chunk("IEND", "")
    end

    private def chunk(type, data)
      [data.bytesize].pack("N") + type.b + data.b + [Zlib.crc32(type + data)].pack("N")
    end

    # Turns a PNG's inflated image data into 8-bit RGBA: undoes each row's
    # filter, pass by pass for an interlaced image, and expands each
    # pixel's samples through the palette and transparency the PNG gives.
    class Decoder # :nodoc:
      def initialize(width:, height:, depth:, color:, interlace:, chunks:)
        @width = width
        @height = height
        @depth = depth
        @color = color
        @interlace = interlace
        @channels = CHANNELS.fetch(color)
        @palette = chunk(chunks, "PLTE")
        @transparency = chunk(chunks, "tRNS")
        raise Error, "is a palette PNG with no PLTE chunk" if color == 3 && @palette.nil?
      end

      def decode(raw)
        return Png.new(width: @width, height: @height, pixels: decode_rows(raw)) if @interlace.zero?

        out = "\0".b * (@width * @height * 4)
        at = 0
        ADAM7.each do |x0, y0, dx, dy|
          columns = (@width - x0 + dx - 1) / dx
          rows = (@height - y0 + dy - 1) / dy
          next if columns <= 0 || rows <= 0

          at = each_line(raw, at, columns, rows) do |line, row|
            pixels = rgba_row(line, columns)
            columns.times do |column|
              out.bytesplice((((y0 + (row * dy)) * @width) + x0 + (column * dx)) * 4, 4, pixels, column * 4, 4)
            end
          end
        end
        Png.new(width: @width, height: @height, pixels: out)
      end

      # The pixels of a PNG that is not interlaced, row after row.
      private def decode_rows(raw)
        rows = [] # : Array[String]
        each_line(raw, 0, @width, @height) { |line, _| rows << rgba_row(line, @width) }
        rows.join
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

          unfilter(filter, line, previous, step)
          yield line, row
          previous = line
          at += stride + 1
        end
        at
      end

      # Undoes one of PNG's five filters (section 9.2) on +line+, in place.
      # These loops run once for every byte of the image, so they are
      # written as plainly as Ruby runs fastest.
      private def unfilter(filter, line, previous, step)
        size = line.size
        index = 0
        case filter
        when 0
          nil
        when 1
          index = step
          while index < size
            line[index] = (line[index] + line[index - step]) & 0xFF
            index += 1
          end
        when 2
          while index < size
            line[index] = (line[index] + previous[index]) & 0xFF
            index += 1
          end
        when 3
          while index < size
            line[index] = (line[index] + ((left(line, index, step) + previous[index]) >> 1)) & 0xFF
            index += 1
          end
        when 4
          while index < size
            up_left = (index >= step) ? previous[index - step] : 0
            line[index] = (line[index] + paeth(left(line, index, step), previous[index], up_left)) & 0xFF
            index += 1
          end
        else
          raise Error, "is a damaged PNG: a row has filter type #{filter}, which PNG does not define"
        end
      end

      private def left(line, index, step)
        (index >= step) ? line[index - step] : 0
      end

      private def paeth(left, up, up_left)
        estimate = left + up - up_left
        to_left = (estimate - left).abs
        to_up = (estimate - up).abs
        to_up_left = (estimate - up_left).abs
        return left if to_left <= to_up && to_left <= to_up_left

        (to_up <= to_up_left) ? up : up_left
      end

      # An unfiltered +line+ of +columns+ pixels as 8-bit RGBA, by the
      # quickest way its color type allows: most icons are RGBA, RGB, or a
      # palette, at 8 bits.
      private def rgba_row(line, columns)
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
