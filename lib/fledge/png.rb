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
  end
end

require_relative "png/filter"
require_relative "png/pixels"
require_relative "png/decoder"
