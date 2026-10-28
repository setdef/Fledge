# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "zlib"

# Fledge::Png reads every kind of PNG the specification defines. These
# tests write their PNGs with an encoder of their own, below, which packs
# samples, filters rows, and interlaces as the W3C's PNG specification
# says, so each kind is read from bytes Fledge::Png did not write.
class PngTest < Minitest::Test
  # The test's own PNG writer.
  module Writer
    module_function def chunk(type, data)
      [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
    end

    # A PNG of +rows+ (each an Array of pixels, each an Array of samples)
    # of color type +color+ at bit depth +depth+, each row filtered with
    # +filter+, Adam7-interlaced when +interlace+ is set.
    module_function def png(rows, color:, depth:, filter: 0, interlace: false, extra: "")
      height = rows.size
      width = rows.first.size
      passes = interlace ? Fledge::Png::ADAM7 : [[0, 0, 1, 1]]
      data = passes.map do |x0, y0, dx, dy|
        picked = (y0...height).step(dy).map { |y| (x0...width).step(dx).map { |x| rows[y][x] } }
        picked = [] if picked.first.nil? || picked.first.empty?
        filtered(picked.map { |row| pack(row, depth) }, filter, [(rows.first.first.size * depth) / 8, 1].max)
      end.join
      header = [width, height, depth, color, 0, 0, interlace ? 1 : 0].pack("NNCCCCC")
      Fledge::Png::SIGNATURE + chunk("IHDR", header) + extra + chunk("IDAT", Zlib::Deflate.deflate(data)) + chunk("IEND", "")
    end

    module_function def pack(pixels, depth)
      samples = pixels.flatten
      case depth
      when 16 then samples.pack("n*")
      when 8 then samples.pack("C*")
      else samples.each_slice(8 / depth).map { |group| group.each_with_index.sum { |value, k| value << (8 - (depth * (k + 1))) } }.pack("C*")
      end
    end

    module_function def filtered(lines, filter, step)
      previous = nil
      lines.map do |line|
        bytes = line.unpack("C*")
        above = previous || Array.new(bytes.size, 0)
        out = bytes.each_index.map do |i|
          left = (i >= step) ? bytes[i - step] : 0
          up_left = (i >= step) ? above[i - step] : 0
          predicted = case filter
          when 0 then 0
          when 1 then left
          when 2 then above[i]
          when 3 then (left + above[i]) / 2
          else paeth(left, above[i], up_left)
          end
          (bytes[i] - predicted) & 0xFF
        end
        previous = bytes
        [filter, *out].pack("C*")
      end.join
    end

    module_function def paeth(left, up, up_left)
      estimate = left + up - up_left
      [left, up, up_left].min_by.with_index { |value, index| [(estimate - value).abs, index] }
    end
  end

  def rgba(png)
    png.pixels.unpack("C*").each_slice(4).to_a
  end

  def test_reads_rgba_through_every_filter
    rows = Array.new(3) { |y| Array.new(5) { |x| [x * 50, y * 100, (x * y * 30) % 256, 255 - (x * 40)] } }
    5.times do |filter|
      png = Fledge::Png.read(Writer.png(rows, color: 6, depth: 8, filter:))
      assert_equal [5, 3], [png.width, png.height], "filter #{filter}"
      assert_equal rows.flatten(1), rgba(png), "filter #{filter}"
    end
  end

  def test_reads_each_color_type_and_depth
    {
      [0, 1] => [[[0], [1], [1]], [[[0, 0, 0, 255], [255, 255, 255, 255], [255, 255, 255, 255]]]],
      [0, 2] => [[[0], [1], [3]], [[[0, 0, 0, 255], [85, 85, 85, 255], [255, 255, 255, 255]]]],
      [0, 4] => [[[15], [5], [0]], [[[255, 255, 255, 255], [85, 85, 85, 255], [0, 0, 0, 255]]]],
      [0, 8] => [[[7], [200], [0]], [[[7, 7, 7, 255], [200, 200, 200, 255], [0, 0, 0, 255]]]],
      [0, 16] => [[[65_535], [0], [32_896]], [[[255, 255, 255, 255], [0, 0, 0, 255], [128, 128, 128, 255]]]],
      [2, 8] => [[[1, 2, 3], [4, 5, 6], [7, 8, 9]], [[[1, 2, 3, 255], [4, 5, 6, 255], [7, 8, 9, 255]]]],
      [2, 16] => [[[65_535, 0, 257], [0, 0, 0], [1, 2, 3]], [[[255, 0, 1, 255], [0, 0, 0, 255], [0, 0, 0, 255]]]],
      [4, 8] => [[[9, 10], [11, 12], [13, 14]], [[[9, 9, 9, 10], [11, 11, 11, 12], [13, 13, 13, 14]]]],
      [4, 16] => [[[65_535, 0], [0, 65_535], [257, 514]], [[[255, 255, 255, 0], [0, 0, 0, 255], [1, 1, 1, 2]]]],
      [6, 16] => [
        [[65_535, 0, 0, 65_535], [0, 0, 0, 0], [0, 65_535, 0, 32_896]],
        [[[255, 0, 0, 255], [0, 0, 0, 0], [0, 255, 0, 128]]],
],
    }.each do |(color, depth), (pixels, expected)|
      png = Fledge::Png.read(Writer.png([pixels], color:, depth:, filter: 1))
      assert_equal expected.first, rgba(png), "color type #{color} at depth #{depth}"
    end
  end

  def test_reads_a_palette_and_its_transparency
    palette = Writer.chunk("PLTE", [255, 0, 0, 0, 255, 0, 0, 0, 255].pack("C*")) + Writer.chunk("tRNS", [128, 0].pack("C*"))
    [2, 4, 8].each do |depth|
      png = Fledge::Png.read(Writer.png([[[0], [1], [2], [1]]], color: 3, depth:, extra: palette))
      assert_equal [[255, 0, 0, 128], [0, 255, 0, 0], [0, 0, 255, 255], [0, 255, 0, 0]], rgba(png), "depth #{depth}"
    end
    png = Fledge::Png.read(Writer.png([[[1], [0], [0], [1], [1]]], color: 3, depth: 1, extra: palette))
    assert_equal [[0, 255, 0, 0], [255, 0, 0, 128], [255, 0, 0, 128], [0, 255, 0, 0], [0, 255, 0, 0]], rgba(png)
  end

  def test_reads_the_one_transparent_color_of_a_gray_or_rgb_image
    gray = Writer.chunk("tRNS", [7].pack("n"))
    assert_equal [[7, 7, 7, 0], [8, 8, 8, 255]], rgba(Fledge::Png.read(Writer.png([[[7], [8]]], color: 0, depth: 8, extra: gray)))

    rgb = Writer.chunk("tRNS", [1, 2, 3].pack("n3"))
    assert_equal [[1, 2, 3, 0], [1, 2, 4, 255]], rgba(Fledge::Png.read(Writer.png([[[1, 2, 3], [1, 2, 4]]], color: 2, depth: 8, extra: rgb)))
  end

  def test_reads_an_interlaced_image
    rows = Array.new(11) { |y| Array.new(9) { |x| [x * 20, y * 20, (x + y) % 256, 255] } }
    [0, 4].each do |filter|
      png = Fledge::Png.read(Writer.png(rows, color: 6, depth: 8, filter:, interlace: true))
      assert_equal rows.flatten(1), rgba(png)
    end
    one = Fledge::Png.read(Writer.png([[[1, 2, 3, 4]]], color: 6, depth: 8, interlace: true))
    assert_equal [[1, 2, 3, 4]], rgba(one)
  end

  def test_writes_what_it_reads
    pixels = [0, 1, 2, 3, 250, 251, 252, 253, 9, 8, 7, 6, 100, 0, 50, 0].pack("C*")
    image = Fledge::Png.new(width: 2, height: 2, pixels:)
    bytes = image.encode
    assert bytes.start_with?(Fledge::Png::SIGNATURE)
    assert_equal image, Fledge::Png.read(bytes)
    assert_equal [2, 2, 8, 6, 0, 0, 0], bytes.byteslice(16, 13).unpack("NNCCCCC")
  end

  def test_refuses_what_is_not_a_png_it_can_read
    good = Writer.png([[[1, 2, 3, 4]]], color: 6, depth: 8)
    damaged = good.dup
    damaged.setbyte(30, damaged.getbyte(30) ^ 1)
    {
      "GIF89a" => "is not a PNG",
      good.byteslice(0, 40) => "ends inside a chunk",
      damaged => "fails its CRC",
      good.sub(Writer.chunk("IEND", ""), "") => "has no IEND chunk",
      Fledge::Png::SIGNATURE + Writer.chunk("IEND", "") => "has no IHDR chunk",
      Writer.png([[[1]]], color: 2, depth: 4) => "bit depth 4",
      Writer.png([[[1]]], color: 5, depth: 8) => "color type 5",
      Writer.png([[[1]]], color: 3, depth: 8) => "no PLTE chunk",
      Writer.png([[[1, 2, 3, 4]]], color: 6, depth: 8, filter: 5) => "filter type 5",
    }.each do |bytes, message|
      error = assert_raises(Fledge::Error, message) { Fledge::Png.read(bytes) }
      assert_includes error.message, message
    end
  end

  def test_refuses_an_image_too_large_or_with_too_little_data
    huge = Fledge::Png::SIGNATURE + Writer.chunk("IHDR", [20_000, 1, 8, 6, 0, 0, 0].pack("NNCCCCC")) + Writer.chunk("IEND", "")
    assert_includes assert_raises(Fledge::Error) { Fledge::Png.read(huge) }.message, "20000x1 pixels"

    short = Fledge::Png::SIGNATURE + Writer.chunk("IHDR", [4, 4, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
      Writer.chunk("IDAT", Zlib::Deflate.deflate("\0\0")) + Writer.chunk("IEND", "")
    assert_includes assert_raises(Fledge::Error) { Fledge::Png.read(short) }.message, "ends early"

    garbage = Fledge::Png::SIGNATURE + Writer.chunk("IHDR", [1, 1, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
      Writer.chunk("IDAT", "not zlib") + Writer.chunk("IEND", "")
    assert_includes assert_raises(Fledge::Error) { Fledge::Png.read(garbage) }.message, "does not inflate"

    palette = Writer.chunk("PLTE", [1, 2, 3].pack("C*"))
    outside = Writer.png([[[5]]], color: 3, depth: 8, extra: palette)
    assert_includes assert_raises(Fledge::Error) { Fledge::Png.read(outside) }.message, "past its palette's end"
  end
end
