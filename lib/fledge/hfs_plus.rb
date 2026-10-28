# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require_relative "entry"
require_relative "error"

module Fledge
  # Writes a Mac OS Extended volume, the file system inside a
  # <tt>.dmg</tt>.
  #
  # A disk image a person opens on a Mac holds a volume macOS mounts, and
  # the volume has to keep what a bundle needs: executable bits, symbolic
  # links, and every byte its signature seals (ADR 009). Apple's
  # +hdiutil+, which writes one, runs only on macOS, and Fledge builds a
  # Mac's app on any computer (ADR 001).
  #
  # This class writes the volume as Apple's Technical Note TN1150 ("HFS
  # Plus Volume Format") defines it, in its case-sensitive variant, HFSX,
  # whose catalog orders names by their UTF-16 code units, so no table of
  # Unicode case folding is needed: the volume header and its copy at the
  # end, the allocation bitmap, an empty extents overflow file, and the
  # catalog B-tree, with a folder or file record and a thread record for
  # each item. Every file's data is one contiguous extent, written as it
  # arrives, so the volume streams to disk. Names are stored decomposed,
  # as HFS Plus requires, and a symbolic link is a file of type +slnk+
  # whose data is its target, as macOS writes one. The volume holds
  # exactly what it is given, and is full: it is written once, to be
  # read.
  #
  # Use it through Fledge::Dmg, which wraps the volume in a disk image.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   File.open("volume.hfs", "w+b") do |io|
  #     volume = Fledge::HfsPlus.new(io, name: "My App")
  #     volume.add(Fledge::Entry.file("hello.txt", "hi\n"))
  #     volume.add(Fledge::Entry.symlink("Applications", "/Applications"))
  #     volume.finish # => 69632, the volume's size in bytes
  #   end
  #--
  # SPDX-SnippetEnd
  #++
  class HfsPlus
    # The allocation block size, in bytes: macOS's default.
    BLOCK = 4096

    # The catalog B-tree's node size, macOS's default for it.
    CATALOG_NODE = 8192

    # The extents overflow B-tree's node size.
    EXTENTS_NODE = 4096

    # Seconds from HFS's epoch, 1904-01-01, to Unix's.
    EPOCH = 2_082_844_800

    # The catalog node IDs TN1150 reserves: the root folder's parent, the
    # root folder, and the special files; the first ID free for items.
    ROOT_PARENT = 1
    # The root folder's catalog node ID.
    ROOT = 2
    # The first catalog node ID an item may have.
    FIRST_ID = 16

    # Record types in the catalog.
    FOLDER_RECORD = 1
    # A file's record.
    FILE_RECORD = 2
    # The record that finds a folder from its ID.
    FOLDER_THREAD = 3
    # The record that finds a file from its ID.
    FILE_THREAD = 4

    # A file record's flag: it has a thread record.
    THREAD_EXISTS = 0x0002

    # A folder record's flag: its last field counts the folders in it,
    # which HFSX requires.
    HAS_FOLDER_COUNT = 0x0010

    # The volume header's attribute: unmounted cleanly.
    UNMOUNTED = 0x0100

    # The owner and group of every item: 99, which macOS shows as the
    # person who mounts the volume.
    UNKNOWN_OWNER = 99

    # Code points HFS Plus keeps whole when it decomposes a name (TN1150,
    # "Unicode Subtleties"): Apple's decomposition leaves these ranges.
    UNDECOMPOSED = [0x2000..0x2FFF, 0xF900..0xFAFF, 0x2F800..0x2FAFF].freeze

    # The most UTF-16 code units a name may hold.
    NAME_MAX = 255

    # An item on the volume, while it is written: its catalog node ID, its
    # parent's, its name, the entry it came from (+nil+ for the root
    # folder), where a file's data is, and how many items and folders a
    # folder holds.
    class Item # :nodoc:
      attr_reader :id, :parent, :name, :entry
      attr_accessor :extent, :children, :folders

      def initialize(id, parent, name, entry)
        @id = id
        @parent = parent
        @name = name
        @entry = entry
        @extent = nil
        @children = 0
        @folders = 0
      end
    end

    # Creates a volume that writes to +io+, an empty file opened for
    # reading and writing in binary.
    #
    # [name] The volume's name, which Finder shows.
    # [mtime] When everything on it was made, as Unix time.
    def initialize(io, name:, mtime: Time.now.to_i)
      @io = io
      @name = name
      @date = mtime + EPOCH
      @next_block = 1
      @next_id = FIRST_ID
      @items = { "" => Item.new(ROOT, ROOT_PARENT, name, nil) }
      @hfs_name = { ROOT => hfs_name(name) }
    end

    # Adds +entry+, whose path is relative to the volume's top, writing a
    # file's bytes at once. A folder it names that is not there yet is
    # added first. Raises Fledge::Error for a path already on the
    # volume, or a name HFS Plus cannot hold.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   volume.add(Fledge::Entry.file("MyApp.app/Contents/Info.plist", plist))
    #--
    # SPDX-SnippetEnd
    #++
    def add(entry)
      parent_path, _, name = entry.path.rpartition("/")
      return if entry.type == :directory && @items.key?(entry.path)
      raise Error, "#{entry.path} is on the volume already" if @items.key?(entry.path)

      parent = folder(parent_path)
      item = Item.new(@next_id, parent.id, name, entry)
      @next_id += 1
      @hfs_name[item.id] = hfs_name(name)
      parent.children += 1
      parent.folders += 1 if entry.type == :directory
      item.extent = write_data((entry.type == :symlink) ? entry.link.b : entry.content.b) unless entry.type == :directory
      @items[entry.path] = item
    end

    # Writes the catalog, the bitmap, and both volume headers, and returns
    # the volume's size in bytes, a whole number of blocks.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   volume.finish # => 69632
    #--
    # SPDX-SnippetEnd
    #++
    def finish
      catalog = catalog_tree
      extents = extents_tree
      extents_start = @next_block
      catalog_start = extents_start + (extents.bytesize / BLOCK)
      allocation_start = catalog_start + (catalog.bytesize / BLOCK)
      total, bitmap_blocks = layout(allocation_start)
      write_at(extents_start, extents)
      write_at(catalog_start, catalog)
      write_at(allocation_start, bitmap(total, bitmap_blocks))
      forks = {
        allocation: fork(allocation_start, bitmap_blocks, bitmap_blocks * BLOCK),
        extents: fork(extents_start, extents.bytesize / BLOCK, extents.bytesize),
        catalog: fork(catalog_start, catalog.bytesize / BLOCK, catalog.bytesize),
      }
      header = volume_header(total, forks)
      @io.seek(1024)
      @io.write(header)
      @io.seek((total * BLOCK) - 1024)
      @io.write(header, "\0" * 512)
      @io.flush
      total * BLOCK
    end

    # +name+ as HFS Plus stores it: its colons as slashes (which a name
    # in macOS's POSIX view cannot hold, and HFS Plus can), decomposed
    # as Apple decomposes it, in UTF-16, big-endian.
    private def hfs_name(name)
      decomposed = name.tr(":", "/").each_char.map do |char|
        (UNDECOMPOSED.any? { |range| range.cover?(char.ord) }) ? char : char.unicode_normalize(:nfd)
      end.join
      utf16 = decomposed.encode(Encoding::UTF_16BE).b
      raise Error, "#{name.inspect} is longer than a Mac's file system allows (#{NAME_MAX} characters)" if utf16.bytesize / 2 > NAME_MAX

      utf16
    rescue EncodingError
      raise Error, "#{name.inspect} is not a name in UTF-8, which a Mac's file system needs"
    end

    private def folder(path)
      return @items.fetch("") if path.empty?

      existing = @items[path]
      if existing
        raise Error, "#{path} is not a folder, so nothing can go in it" unless existing.entry&.type == :directory

        return existing
      end
      add(Entry.directory(path))
      @items.fetch(path)
    end

    # Writes +bytes+ at the next free block and returns the extent,
    # <tt>[first block, blocks, bytes]</tt>.
    private def write_data(bytes)
      return [0, 0, 0] if bytes.empty?

      start = @next_block
      write_at(start, bytes)
      blocks = (bytes.bytesize + BLOCK - 1) / BLOCK
      @next_block += blocks
      [start, blocks, bytes.bytesize]
    end

    private def write_at(block, bytes)
      @io.seek(block * BLOCK)
      @io.write(bytes)
      padding = -bytes.bytesize % BLOCK
      @io.write("\0" * padding) if padding.positive?
    end

    # The volume's size in blocks and the bitmap's, for a bitmap that
    # begins at +start+: the bitmap holds a bit for each block, itself
    # included, and the last block holds the second volume header.
    private def layout(start)
      bitmap_blocks = 1
      loop do
        total = start + bitmap_blocks + 1
        needed = (((total + 7) / 8) + BLOCK - 1) / BLOCK
        return [total, bitmap_blocks] if needed <= bitmap_blocks

        bitmap_blocks = needed
      end
    end

    # Every block in use: the volume holds what it was given and no more.
    private def bitmap(total, blocks)
      bits = ("\xFF".b * (total / 8)) + ((total % 8).zero? ? "".b : [(0xFF << (8 - (total % 8))) & 0xFF].pack("C"))
      bits + ("\0".b * ((blocks * BLOCK) - bits.bytesize))
    end

    # An HFSPlusForkData of one extent.
    private def fork(start, blocks, size)
      extents = blocks.zero? ? [0, 0] : [start, blocks]
      [size, 0, blocks, *extents].pack("Q>NNNN") + ("\0" * 56)
    end

    private def volume_header(total, forks)
      files = @items.values.count { |item| item.entry && item.entry.type != :directory }
      folders = @items.values.count { |item| item.entry&.type == :directory }
      finder = [0, 0, ROOT, 0, 0, 0, *volume_id.unpack("NN")]
      [
        "HX",
        5,
        UNMOUNTED,
        "10.0",
        0,
        @date,
        @date,
        0,
        @date,
        files,
        folders,
        BLOCK,
        total,
        0,
        0,
        65_536,
        65_536,
        @next_id,
        1,
        1,
        *finder,
      ].pack("a2nNa4N NNNN NNNNNN NNNNQ> N8") +
        forks.fetch(:allocation) + forks.fetch(:extents) + forks.fetch(:catalog) +
        fork(0, 0, 0) + fork(0, 0, 0)
    end

    # A 64-bit volume ID, the same for the same volume.
    private def volume_id
      digest = Digest::SHA256.new
      @items.each { |path, item| digest << path << item.extent.to_s }
      digest.digest[0, 8].to_s
    end

    # The extents overflow file: a B-tree with its header node and no
    # records, since every file is one extent.
    private def extents_tree
      header_node(EXTENTS_NODE, depth: 0, root: 0, leaf_records: 0, first_leaf: 0, last_leaf: 0, total: 1,
        max_key: 10, compare: 0, attributes: 0x2)
    end

    private def catalog_tree
      records = catalog_records.sort_by { |key, _| [key.byteslice(2, 4), key.byteslice(8..)] }
      leaves = pack_nodes(records.map { |key, data| key + data }, records.map(&:first), kind: -1, height: 1, first: 1)
      levels = [leaves]
      until levels.last.size == 1
        below = levels.last
        start = below.last[:number] + 1
        index = below.map { |node| node[:first_key] + [node[:number]].pack("N") }
        levels << pack_nodes(index, below.map { |node| node[:first_key] }, kind: 0, height: levels.size + 1, first: start)
      end
      nodes = levels.flatten
      header = header_node(CATALOG_NODE, depth: levels.size, root: nodes.last[:number], leaf_records: records.size,
        first_leaf: leaves.first[:number], last_leaf: leaves.last[:number], total: nodes.size + 1,
        max_key: 516, compare: 0xBC, attributes: 0x6)
      header + nodes.map { |node| node[:bytes] }.join
    end

    # The catalog's records, <tt>[key, record]</tt>: each item's record
    # under its parent and name, and its thread record under its own ID.
    private def catalog_records
      records = [] # : Array[[String, String]]
      @items.each_value do |item|
        name = @hfs_name.fetch(item.id)
        entry = item.entry
        type = (entry.nil? || entry.type == :directory) ? FOLDER_THREAD : FILE_THREAD
        records << [key(item.parent, name), record(item)]
        records << [key(item.id, "".b), [type, 0, item.parent, name.bytesize / 2].pack("nnNn") + name]
      end
      records
    end

    private def key(parent, name)
      [6 + name.bytesize, parent, name.bytesize / 2].pack("nNn") + name
    end

    private def record(item)
      entry = item.entry
      return folder_record(item, 0o040755) if entry.nil?
      return folder_record(item, 0o040000 | (entry.mode & 0o7777)) if entry.type == :directory

      symlink = entry.type == :symlink
      mode = symlink ? 0o120755 : 0o100000 | (entry.mode & 0o7777)
      user_info = symlink ? ["slnk", "rhap", 0, 0, 0].pack("a4a4nNn") : "\0" * 16
      start, blocks, size = item.extent || [0, 0, 0]
      [FILE_RECORD, THREAD_EXISTS, 0, item.id, @date, @date, @date, @date, 0].pack("nnNNNNNNN") +
        permissions(mode) + user_info + ("\0" * 16) + [0, 0].pack("NN") +
        fork(start, blocks, size) + fork(0, 0, 0)
    end

    private def folder_record(item, mode)
      [FOLDER_RECORD, HAS_FOLDER_COUNT, item.children, item.id, @date, @date, @date, @date, 0].pack("nnNNNNNNN") +
        permissions(mode) + ("\0" * 32) + [0, item.folders].pack("NN")
    end

    private def permissions(mode)
      [UNKNOWN_OWNER, UNKNOWN_OWNER, 0, 0, mode, 0].pack("NNCCnN")
    end

    # Packs +records+ into B-tree nodes of CATALOG_NODE bytes, numbered
    # from +first+ and linked to each other, and returns each node's
    # number, bytes, and first key.
    private def pack_nodes(records, keys, kind:, height:, first:)
      groups = [] # : Array[Array[Integer]]
      used = 0
      records.each_with_index do |record, index|
        if groups.empty? || 14 + used + record.bytesize + (2 * (groups.last.size + 2)) > CATALOG_NODE
          groups << []
          used = 0
        end
        groups.last << index
        used += record.bytesize
      end
      groups.each_with_index.map do |group, position|
        number = first + position
        forward = (position + 1 < groups.size) ? number + 1 : 0
        backward = position.positive? ? number - 1 : 0
        { number:, first_key: keys.fetch(group.first), bytes: node(kind, height, forward, backward, group.map { |index| records.fetch(index) }) }
      end
    end

    private def node(kind, height, forward, backward, records, size: CATALOG_NODE)
      body = [forward, backward, kind, height, records.size, 0].pack("NNcCnn")
      offsets = [] # : Array[Integer]
      records.each do |record|
        offsets << body.bytesize
        body << record
      end
      offsets << body.bytesize
      body + ("\0" * (size - body.bytesize - (2 * offsets.size))) + offsets.reverse.pack("n*")
    end

    private def header_node(size, depth:, root:, leaf_records:, first_leaf:, last_leaf:, total:, max_key:, compare:, attributes:)
      header = [
        depth,
        root,
        leaf_records,
        first_leaf,
        last_leaf,
        size,
        max_key,
        total,
        0,
        0,
        size * total,
        0,
        compare,
        attributes,
].pack("nNNNNnnNNnNCCN") + ("\0" * 64)
      map = ("\0".b * (size - 256))
      raise Error, "the volume holds too many files for one catalog map" if total > map.bytesize * 8

      (total / 8).times { |index| map.setbyte(index, 0xFF) }
      map.setbyte(total / 8, (0xFF << (8 - (total % 8))) & 0xFF) unless (total % 8).zero?
      node(1, 0, 0, 0, [header, "\0" * 128, map], size:)
    end
  end
end
