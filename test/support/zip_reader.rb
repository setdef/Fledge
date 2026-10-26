# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"

# Reads a .zip the way an unzip tool does, from the end: the end of
# central directory record, then each central directory header, then
# the local header and data it points to. It is written from the
# specification (PKWARE's APPNOTE.TXT, sections 4.3.7, 4.3.12, and
# 4.3.16), independently of Fledge::Zip, so tests can check what the
# writer wrote rather than what it meant to write. It raises on any
# disagreement between a central header and its local header, and on a
# CRC-32 that does not match the data.
module ZipReader
  # One member of the archive, as its central directory describes it,
  # with its data inflated.
  Member = Data.define(:name, :flags, :method, :crc, :compressed_size, :size, :made_by, :external, :dos_time,
    :dos_date, :data)

  def self.read(path)
    bytes = File.binread(path)
    eocd = bytes.rindex([0x06054b50].pack("V")) or raise "no end of central directory record"
    _, disk, cd_disk, on_disk, total, cd_size, cd_offset, comment = bytes.byteslice(eocd, 22).unpack("VvvvvVVv")
    raise "multi-disk archive" unless disk.zero? && cd_disk.zero? && on_disk == total
    raise "archive comment present" unless comment.zero?
    raise "central directory does not end at the EOCD" unless cd_offset + cd_size == eocd

    members = []
    offset = cd_offset
    total.times do
      members << central(bytes, offset)
      offset += 46 + bytes.byteslice(offset + 28, 6).unpack("vvv").sum
    end
    raise "central directory size disagrees" unless offset == eocd

    members
  end

  def self.central(bytes, offset)
    fields = bytes.byteslice(offset, 46).unpack("VvvvvvvVVVvvvvvVV")
    signature, made_by, _needed, flags, method, time, date, crc, compressed, size, name_length, extra_length,
      comment_length, _disk, _internal, external, local_offset = fields
    raise "bad central header signature" unless signature == 0x02014b50
    raise "unexpected extra field or comment" unless extra_length.zero? && comment_length.zero?

    name = bytes.byteslice(offset + 46, name_length)
    data = local_data(bytes, local_offset, name, [flags, method, time, date, crc, compressed, size])
    name = name.force_encoding((flags & 0x0800).zero? ? Encoding::BINARY : Encoding::UTF_8)
    Member.new(name:, flags:, method:, crc:, compressed_size: compressed, size:, made_by:, external:, dos_time: time,
      dos_date: date, data:)
  end

  def self.local_data(bytes, offset, name, central)
    fields = bytes.byteslice(offset, 30).unpack("VvvvvvVVVvv")
    signature, _needed, *local, name_length, extra_length = fields
    raise "bad local header signature for #{name}" unless signature == 0x04034b50
    raise "local header disagrees with central header for #{name}" unless local == central
    raise "local name differs for #{name}" unless bytes.byteslice(offset + 30, name_length) == name

    _flags, method, _time, _date, crc, compressed, size = central
    raw = bytes.byteslice(offset + 30 + name_length + extra_length, compressed)
    data = case method
    when 0 then raw
    when 8 then Zlib::Inflate.new(-Zlib::MAX_WBITS).then { |inflate| inflate.inflate(raw).tap { inflate.close } }
    else raise "unknown method #{method}"
    end
    raise "size disagrees for #{name}" unless data.bytesize == size
    raise "CRC-32 disagrees for #{name}" unless Zlib.crc32(data) == crc

    data
  end
end
