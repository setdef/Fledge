# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class IconTest < Minitest::Test
  # A square image of +side+ pixels, its left half opaque red and its
  # right half transparent green.
  def self.image(side)
    row = ([255, 0, 0, 255] * (side / 2)) + ([0, 255, 0, 0] * (side - (side / 2)))
    Fledge::Png.new(width: side, height: side, pixels: (row * side).pack("C*"))
  end

  # One icon for every test that only reads it: making each size takes a
  # moment.
  def icon
    self.class.instance_variable_get(:@icon) || self.class.instance_variable_set(:@icon, Fledge::Icon.new(IconTest.image(1024)))
  end

  def pixel(image, x, y)
    image.pixels.byteslice(((y * image.width) + x) * 4, 4).unpack("C4")
  end

  def test_reads_a_square_png_of_at_least_1024_pixels
    Dir.mktmpdir do |dir|
      path = File.join(dir, "icon.png")
      File.binwrite(path, IconTest.image(1024).encode)
      assert_equal 1024, Fledge::Icon.read(path).image(1024).width

      File.binwrite(path, IconTest.image(512).encode)
      error = assert_raises(Fledge::Error) { Fledge::Icon.read(path) }
      assert_equal "the icon #{path} is 512x512 pixels; use a square PNG of at least 1024x1024", error.message

      File.binwrite(path, Fledge::Png.new(width: 1024, height: 1025, pixels: "\0".b * (1024 * 1025 * 4)).encode)
      assert_match(/is 1024x1025 pixels/, assert_raises(Fledge::Error) { Fledge::Icon.read(path) }.message)

      File.write(path, "not a png")
      assert_equal "the icon #{path} is not a PNG", assert_raises(Fledge::Error) { Fledge::Icon.read(path) }.message
      assert_equal "the icon #{dir}/none.png does not exist",
        assert_raises(Fledge::Error) { Fledge::Icon.read(File.join(dir, "none.png")) }.message
    end
  end

  # Each new pixel averages the old ones it covers, weighing each one's
  # color by its alpha: where opaque red meets transparent green, the
  # result is half as opaque, and red, not a muddy mix.
  def test_shrinks_by_averaging_and_weighs_color_by_alpha
    small = icon.image(16)
    assert_equal [16, 16], [small.width, small.height]
    assert_equal [255, 0, 0, 255], pixel(small, 0, 0)
    assert_equal [0, 0, 0, 0], pixel(small, 15, 15)

    edge = Fledge::Png.new(width: 2, height: 2, pixels: [255, 0, 0, 255, 0, 255, 0, 0, 255, 0, 0, 255, 0, 255, 0, 0].pack("C*"))
    assert_equal [255, 0, 0, 128], pixel(Fledge::Icon::Resampler.shrink(edge, 1), 0, 0)

    thirds = Fledge::Png.new(width: 3, height: 1, pixels: [0, 0, 0, 255, 255, 255, 255, 255, 30, 60, 90, 255].pack("C*"))
    shrunk = Fledge::Icon::Resampler.shrink(thirds, 2)
    assert_equal [[85, 85, 85, 255], [105, 125, 145, 255]], [pixel(shrunk, 0, 0), pixel(shrunk, 1, 0)]
  end

  def test_writes_pngs_of_any_size
    [16, 20, 48, 512].each do |size|
      image = Fledge::Png.read(icon.png(size))
      assert_equal [size, size], [image.width, image.height]
    end
  end

  # Apple's icon family: "icns", the file's length, then each type, its
  # length, and a PNG of its size, all big-endian.
  def test_writes_an_icns_of_every_size_macos_asks_for
    icns = icon.icns
    assert_equal "icns", icns.byteslice(0, 4)
    assert_equal icns.bytesize, icns.byteslice(4, 4).unpack1("N")
    found = []
    at = 8
    while at < icns.bytesize
      type, length = icns.byteslice(at, 8).unpack("a4N")
      found << [type, Fledge::Png.read(icns.byteslice(at + 8, length - 8)).width]
      at += length
    end
    assert_equal [
      ["icp4", 16],
      ["icp5", 32],
      ["ic11", 32],
      ["ic12", 64],
      ["ic07", 128],
      ["ic13", 256],
      ["ic08", 256],
      ["ic14", 512],
      ["ic09", 512],
      ["ic10", 1024],
], found
  end

  # An .ico (Microsoft's "Icons"): an ICONDIR of type 1, then an entry for
  # each image, whose width and height are 0 for 256, saying how long it
  # is and where, then the images themselves.
  def test_writes_an_ico_of_the_windows_images
    ico = icon.ico
    images = icon.windows_images

    assert_equal [0, 1, images.size], ico.unpack("vvv")
    offset = 6 + (16 * images.size)
    images.each_with_index do |(size, data), index|
      width, height, colors, _, planes, bits, length, at = ico.byteslice(6 + (16 * index), 16).unpack("CCCCvvVV")
      assert_equal [size % 256, size % 256, 0, 1, 32, data.bytesize, offset], [width, height, colors, planes, bits, length, at]
      assert_equal data, ico.byteslice(at, length)
      offset += length
    end
    assert_equal offset, ico.bytesize
  end

  # A Windows icon's images: 32-bit bitmaps, bottom row first, in BGRA,
  # with an all-zero AND mask, and a PNG at 256.
  def test_writes_windows_icon_images
    images = icon.windows_images
    assert_equal [16, 20, 24, 32, 40, 48, 64, 96, 256], images.map(&:first)
    assert Fledge::Png.read(images.last.last)

    size, bitmap = images.first
    header = bitmap.byteslice(0, 40).unpack("Vl<l<vvVVl<l<VV")
    assert_equal [40, 16, 32, 1, 32, 0], header.first(6)
    assert_equal 40 + (16 * 16 * 4) + (4 * 16), bitmap.bytesize
    assert_equal [0, 0, 255, 255], bitmap.byteslice(40, 4).unpack("C4"), "the bottom row's first pixel, red, as BGRA"
    assert_equal "\0" * 64, bitmap.byteslice(40 + (size * size * 4), 64)
  end
end
