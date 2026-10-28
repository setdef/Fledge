# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "zlib"
require_relative "plist"

module Fledge
  # Writes Apple's Universal Disk Image Format, the <tt>.dmg</tt> a Mac
  # opens with a double-click.
  #
  # A volume Fledge::HfsPlus writes is as large as everything on it, and
  # a disk image a person downloads should be compressed. macOS reads a
  # compressed image only in its own format, which +hdiutil+, a macOS
  # program, writes; notarization staples its ticket to one too (Plan
  # 002, "Signing and notarization").
  #
  # This module writes a read-only, zlib-compressed image ("UDZO", as
  # <tt>hdiutil create -format UDZO</tt> names it) of one volume with no
  # partition map, laid out as <tt>hdiutil create -layout NONE</tt> lays
  # one out, which hdiutil itself served as the oracle for: the
  # compressed chunks of the volume, a property list whose +blkx+
  # resource describes each chunk of 2048 sectors (zlib, or zeros, which
  # take no space), and the 512-byte +koly+ trailer that finds it all.
  # The checksums are CRC-32s, as hdiutil writes them: one of the volume's
  # bytes, in its +blkx+ entry, and one of that checksum, in the trailer.
  # The image's ID is a hash of the image, so the same volume makes the
  # same image.
  #
  # Use it through Fledge::Dmg.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   File.open("volume.hfs", "rb") do |volume|
  #     Fledge::Udif.write(volume, to: "MyApp.dmg", partition: "Apple_HFSX")
  #   end
  #--
  # SPDX-SnippetEnd
  #++
  module Udif
    # A sector, the unit an image counts in.
    SECTOR = 512

    # Sectors in each chunk: hdiutil's, a mebibyte.
    CHUNK = 2048

    # Chunk types (a +blkx+ entry's), as hdiutil writes them.
    ZERO = 0x00000000
    # Bytes stored as they are.
    RAW = 0x00000001
    # Bytes compressed with zlib.
    ZLIB = 0x80000005
    # The entry that ends a +blkx+ table.
    TERMINATOR = 0xFFFFFFFF

    # The checksum type both checksums have: CRC-32.
    CRC32 = 2

    # Writes the image of the volume read from +volume+, an IO at its
    # start, to the path +to+, as a single partition of type +partition+,
    # such as <tt>"Apple_HFSX"</tt>. Returns +to+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Udif.write(volume, to: "MyApp.dmg", partition: "Apple_HFSX") # => "MyApp.dmg"
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(volume, to:, partition:)
      File.open(to, "wb") do |out|
        chunks, crc, sectors = write_chunks(volume, out)
        data_length = out.pos
        table = blkx(chunks, crc, sectors)
        name = "whole disk (#{partition} : 0)"
        xml = Plist.write({
"resource-fork" => {
"blkx" => [
{
"Attributes" => "0x0050",
"CFName" => name,
"Data" => Plist::Bytes.new(bytes: table),
"ID" => "0",
"Name" => name,
},
],
},
})
        out.write(xml)
        out.write(trailer(data_length, xml.bytesize, crc, sectors, Digest::SHA256.digest(table + xml)))
      end
      to
    end

    # Writes each chunk of the volume to +out+, and returns the chunks'
    # entries, the CRC-32 of the volume, and its size in sectors.
    private_class_method def self.write_chunks(volume, out) # :nodoc:
      chunks = [] # : Array[[Integer, Integer, Integer, Integer, Integer]]
      crc = 0
      sector = 0
      while (bytes = volume.read(CHUNK * SECTOR))
        count = (bytes.bytesize + SECTOR - 1) / SECTOR
        bytes += "\0" * ((count * SECTOR) - bytes.bytesize)
        crc = Zlib.crc32(bytes, crc)
        if bytes.count("\0") == bytes.bytesize
          chunks << [ZERO, sector, count, out.pos, 0]
        else
          compressed = Zlib::Deflate.deflate(bytes, Zlib::BEST_COMPRESSION)
          type, stored = (compressed.bytesize < bytes.bytesize) ? [ZLIB, compressed] : [RAW, bytes]
          chunks << [type, sector, count, out.pos, stored.bytesize]
          out.write(stored)
        end
        sector += count
      end
      [chunks, crc, sector]
    end

    # The +mish+ table: where each chunk of the volume is, and how it is
    # stored.
    private_class_method def self.blkx(chunks, crc, sectors) # :nodoc:
      entries = chunks + [[TERMINATOR, sectors, 0, 0, 0]]
      header = ["mish", 1, 0, sectors, 0, CHUNK + 8, 0xFFFFFFFE].pack("a4NQ>Q>Q>NN") + ("\0" * 24) +
        checksum(crc) + [entries.size].pack("N")
      header + entries.map { |type, sector, count, offset, length| [type, 0, sector, count, offset, length].pack("NNQ>Q>Q>Q>") }.join
    end

    # A UDIF checksum: its type, its size in bits, and 128 bytes holding
    # it.
    private_class_method def self.checksum(crc) # :nodoc:
      [CRC32, 32, crc].pack("NNN") + ("\0" * 124)
    end

    private_class_method def self.trailer(data_length, xml_length, crc, sectors, digest) # :nodoc:
      master = Zlib.crc32([crc].pack("N"))
      ["koly", 4, 512, 1, 0, 0, data_length, 0, 0, 1, 1].pack("a4NNNQ>Q>Q>Q>Q>NN") + digest[0, 16].to_s +
        [0, 0].pack("NN") + ("\0" * 128) + [data_length, xml_length].pack("Q>Q>") + ("\0" * 120) +
        checksum(master) + [2, sectors].pack("NQ>") + ("\0" * 12)
    end
  end
end
