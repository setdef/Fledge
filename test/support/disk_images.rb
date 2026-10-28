# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "open3"
require "zlib"

# Reads back what Fledge::Udif and Fledge::HfsPlus write, by the formats'
# own documents (Apple's TN1150 for the volume; the koly trailer and mish
# table hdiutil writes, for the image), so tests can check every byte the
# writers lay down on any computer. On a Mac, MacDisk attaches an image
# with Apple's own hdiutil, the oracle.
module DiskImages
  # The volume inside a UDIF image at +path+: the koly trailer, the mish
  # table it finds through the XML property list, and the bytes of every
  # chunk, decompressed.
  def self.udif(path)
    bytes = File.binread(path)
    koly = bytes.byteslice(-512, 512).to_s
    xml_offset, xml_length = koly.byteslice(216, 16).to_s.unpack("Q>2")
    xml = bytes.byteslice(xml_offset, xml_length).to_s
    table = xml[%r{<data>(.*?)</data>}m, 1].to_s.unpack1("m")
    chunks = table.byteslice(200, 4).to_s.unpack1("N").times.map { |index| table.byteslice(204 + (40 * index), 40).to_s.unpack("NNQ>Q>Q>Q>") }
    volume = chunks.map do |type, _, _, count, offset, length|
      case type
      when 0x80000005 then Zlib::Inflate.inflate(bytes.byteslice(offset, length))
      when 0x00000001 then bytes.byteslice(offset, length)
      when 0 then "\0" * (count * 512)
      else ""
      end
    end.join
    { koly:, xml:, table:, chunks:, volume: }
  end

  # The items of the Mac OS Extended volume +volume+ (bytes), by path:
  # each with its catalog record's type, mode, and, for a file or link,
  # its data fork's bytes; and the volume header's fields.
  class Hfs
    attr_reader :header, :items, :keys

    def initialize(volume)
      @volume = volume
      @header = volume.byteslice(1024, 512).to_s
      @block = @header.byteslice(40, 4).to_s.unpack1("N")
      @catalog = fork_bytes(@header.byteslice(272, 80).to_s)
      @items = {}
      @keys = []
      read_catalog
    end

    def signature = @header.byteslice(0, 2)

    def version = @header.byteslice(2, 2).to_s.unpack1("n")

    def file_count = @header.byteslice(32, 4).to_s.unpack1("N")

    def folder_count = @header.byteslice(36, 4).to_s.unpack1("N")

    def total_blocks = @header.byteslice(44, 4).to_s.unpack1("N")

    def block_size = @block

    def catalog_depth = @catalog.byteslice(14, 2).to_s.unpack1("n")

    private def fork_bytes(fork)
      size, _, _, start, count = fork.unpack("Q>NNNN")
      @volume.byteslice(start * @block, count * @block).to_s.byteslice(0, size).to_s
    end

    private def read_catalog
      node_size = @catalog.byteslice(14 + 18, 2).to_s.unpack1("n")
      first_leaf = @catalog.byteslice(14 + 10, 4).to_s.unpack1("N")
      records = []
      number = first_leaf
      until number.zero?
        node = @catalog.byteslice(number * node_size, node_size).to_s
        forward, _, _, _, count = node.unpack("NNcCn")
        count.times do |index|
          start = node.byteslice(node_size - (2 * (index + 1)), 2).to_s.unpack1("n")
          records << node.byteslice(start, node_size - start).to_s
        end
        number = forward
      end
      names = { 1 => nil }
      parsed = records.map { |record| parse(record) }
      parsed.each { |key, data| names[data[:id]] = [key[:parent], key[:name]] if data[:id] }
      parsed.each do |key, data|
        @keys << [key[:parent], key[:name]]
        next unless data[:id]

        @items[path(data[:id], names)] = data
      end
    end

    private def parse(record)
      key_length, parent, name_length = record.unpack("nNn")
      name = record.byteslice(8, name_length * 2).to_s.force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8)
      data = record.byteslice((2 + key_length)..).to_s
      type = data.unpack1("n")
      key = { parent:, name:, raw_name: record.byteslice(8, name_length * 2) }
      case type
      when 1 then [
        key,
        {
        type: :folder,
        id: data.byteslice(8, 4).to_s.unpack1("N"),
        valence: data.byteslice(4, 4).to_s.unpack1("N"),
        flags: data.byteslice(2, 2).to_s.unpack1("n"),
        folders: data.byteslice(84, 4).to_s.unpack1("N"),
        mode: data.byteslice(42, 2).to_s.unpack1("n"),
},
]
      when 2 then [
        key,
        {
        type: :file,
        id: data.byteslice(8, 4).to_s.unpack1("N"),
        flags: data.byteslice(2, 2).to_s.unpack1("n"),
        mode: data.byteslice(42, 2).to_s.unpack1("n"),
        user_info: data.byteslice(48, 8),
        content: fork_bytes(data.byteslice(88, 80).to_s),
},
]
      else [key, { type: :thread }]
      end
    end

    private def path(id, names)
      parts = []
      while (entry = names[id])
        parent, name = entry
        break if parent == 1

        parts.unshift(name)
        id = parent
      end
      parts.join("/")
    end
  end

  # A disk image attached with hdiutil, on a Mac: yields the folder it is
  # mounted at, and detaches it afterwards. Raw volumes attach as raw
  # disk images.
  def self.mounted(path, raw: false)
    mount = Dir.mktmpdir("fledge-mount")
    command = ["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount]
    command += ["-imagekey", "diskimage-class=CRawDiskImage"] if raw
    out, status = Open3.capture2e(*command, path)
    raise "hdiutil attach failed: #{out}" unless status.success?

    begin
      yield mount
    ensure
      system("hdiutil", "detach", "-quiet", mount)
      FileUtils.rm_rf(mount)
    end
  end
end
