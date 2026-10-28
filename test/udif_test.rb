# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/disk_images"
require "open3"
require "zlib"

# Fledge::Udif, read back by the layout hdiutil writes, and, on a Mac,
# verified and attached by hdiutil itself.
class UdifTest < Minitest::Test
  def image(dir, volume)
    path = File.join(dir, "image.dmg")
    Fledge::Udif.write(StringIO.new(volume), to: path, partition: "Apple_HFSX")
    path
  end

  # A volume of a compressible mebibyte, a zero one, and a random one,
  # which zlib cannot shrink, so it is stored as it is.
  def volume
    ("text " * 209_716).byteslice(0, 1_048_576).to_s + ("\0" * 1_048_576) + Random.new(1).bytes(512 * 100)
  end

  def test_the_trailer_finds_the_property_list_after_the_chunks
    Dir.mktmpdir do |dir|
      path = image(dir, volume)
      read = DiskImages.udif(path)
      koly = read[:koly]

      assert_equal ["koly", 4, 512, 1], koly.unpack("a4NNN")
      data_length = koly.byteslice(32, 8).to_s.unpack1("Q>")
      assert_equal [data_length, read[:xml].bytesize], koly.byteslice(216, 16).to_s.unpack("Q>2")
      assert_equal File.size(path), data_length + read[:xml].bytesize + 512
      assert_equal (volume.bytesize / 512), koly.byteslice(492, 8).to_s.unpack1("Q>")
      assert_includes read[:xml], "<string>whole disk (Apple_HFSX : 0)</string>"
    end
  end

  def test_each_chunk_is_zlib_zeros_or_raw_and_together_they_are_the_volume
    Dir.mktmpdir do |dir|
      read = DiskImages.udif(image(dir, volume))

      assert_equal [0x80000005, 0, 1, 0xFFFFFFFF], read[:chunks].map(&:first)
      assert_equal [0, 2048, 4096, 4196], read[:chunks].map { |chunk| chunk[2] }
      assert_equal [0, 0], read[:chunks][1].values_at(1, 5)
      assert_equal volume, read[:volume]
    end
  end

  # hdiutil's checksums: the CRC-32 of the volume in the mish table, and
  # the CRC-32 of that checksum in the trailer.
  def test_the_checksums_are_hdiutils_crc32s
    Dir.mktmpdir do |dir|
      read = DiskImages.udif(image(dir, volume))
      crc = Zlib.crc32(volume)

      assert_equal [2, 32, crc], read[:table].byteslice(64, 12).to_s.unpack("NNN")
      assert_equal [2, 32, Zlib.crc32([crc].pack("N"))], read[:koly].byteslice(352, 12).to_s.unpack("NNN")
    end
  end

  def test_the_same_volume_makes_the_same_image
    Dir.mktmpdir do |dir|
      first = File.binread(image(dir, volume))

      assert_equal first, File.binread(image(dir, volume))
    end
  end

  def test_hdiutil_verifies_and_attaches_the_image
    skip "hdiutil is macOS's" unless RUBY_PLATFORM.include?("darwin")

    Dir.mktmpdir do |dir|
      io = StringIO.new("".b)
      hfs = Fledge::HfsPlus.new(io, name: "Checked")
      hfs.add(Fledge::Entry.file("hello.txt", "hello\n"))
      hfs.finish
      path = image(dir, io.string)

      out, status = Open3.capture2e("hdiutil", "verify", path)
      assert_predicate status, :success?, out
      out, = Open3.capture2e("hdiutil", "imageinfo", path)
      assert_includes out, "Format: UDZO"
      DiskImages.mounted(path) { |mount| assert_equal "hello\n", File.read(File.join(mount, "hello.txt")) }
    end
  end
end
