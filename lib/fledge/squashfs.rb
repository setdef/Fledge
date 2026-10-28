# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "zlib"
require_relative "entry"
require_relative "error"
require_relative "squashfs/inodes"
require_relative "squashfs/metadata"
require_relative "squashfs/node"

module Fledge
  # Writes a SquashFS 4.0 file system, the one an AppImage carries.
  #
  # An AppImage is a program that mounts the file system appended to it
  # and runs what it holds (ADR 009). The tools that write one,
  # +mksquashfs+ and +appimagetool+, run only on Linux, and Fledge builds
  # a Linux app on any computer (ADR 001).
  #
  # This class writes the format as squashfs-tools-ng's
  # <tt>doc/format.adoc</tt> specifies it, compressed with zlib (the
  # format's "gzip", which Ruby's standard library writes): each file's
  # data in blocks of BLOCK_SIZE, compressed one by one, as it arrives,
  # with the tail of each file packed into shared fragment blocks; then
  # the inode table and the directory table, in metadata blocks of 8 KiB,
  # each directory's entries sorted by their bytes; the fragment table;
  # and the table of the one owner every item has, root, as an AppImage
  # needs no other. Permissions are the entries', and modification times
  # the build's. There are no extended attributes, no export table, and
  # no hard links.
  #
  # Use it through Fledge::AppImage.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   File.open("app.squashfs", "wb") do |io|
  #     squashfs = Fledge::Squashfs.new(io)
  #     squashfs.add(Fledge::Entry.file("AppRun", launcher, mode: 0o755))
  #     squashfs.finish # => 4096, the bytes it wrote
  #   end
  #--
  # SPDX-SnippetEnd
  #++
  class Squashfs
    # The data block size: squashfs-tools' default, 128 KiB.
    BLOCK_SIZE = 131_072

    # The uncompressed size of a metadata block.
    METADATA = 8192

    # The format's magic number, "hsqs" on disk.
    MAGIC = 0x73717368

    # The compressor's ID: zlib.
    GZIP = 1

    # The superblock flag that says there are no extended attributes.
    NO_XATTRS = 0x0200

    # The size bit of a block stored uncompressed.
    UNCOMPRESSED = 1 << 24

    # A metadata block's header bit for one stored uncompressed.
    METADATA_UNCOMPRESSED = 0x8000

    # Basic inode types.
    DIRECTORY = 1
    # A regular file's inode type.
    FILE = 2
    # A symbolic link's inode type.
    SYMLINK = 3
    # A directory whose listing is larger than a basic one holds.
    EXTENDED_DIRECTORY = 8

    # A reference to no table, or to no fragment.
    NONE = 0xFFFF_FFFF_FFFF_FFFF

    # The most entries one directory header may lead.
    RUN = 256

    # The most bytes a name may have.
    NAME_MAX = 256

    # The superblock's size.
    SUPERBLOCK = 96

    # Creates a file system that writes to +io+, from where +io+ is now:
    # its offsets are counted from there, so it can follow an AppImage's
    # runtime in the same file.
    #
    # [mtime] When everything in it was made, as Unix time.
    def initialize(io, mtime: Time.now.to_i)
      @io = io
      @base = io.pos
      @mtime = mtime
      @root = Node.new(Entry.directory("top"))
      @fragments = [] # : Array[[Integer, Integer]]
      @fragment = "".b
      @io.write("\0" * SUPERBLOCK)
    end

    # Adds +entry+, whose path is relative to the file system's top,
    # writing a file's bytes at once. A folder it names that is not there
    # yet is added first. Raises Fledge::Error for a path already in it,
    # or a name longer than NAME_MAX bytes.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   squashfs.add(Fledge::Entry.symlink("AppRun", "MyApp"))
    #--
    # SPDX-SnippetEnd
    #++
    def add(entry)
      *parents, name = entry.path.split("/")
      raise Error, "#{name} is a longer name than an AppImage can hold (#{NAME_MAX} bytes)" if name.to_s.bytesize > NAME_MAX

      folder = parents.inject(@root) { |node, part| child_folder(node, part, entry.path) }
      existing = folder.children[name]
      return if existing && existing.entry.type == :directory && entry.type == :directory
      raise Error, "#{entry.path} is in the AppImage already" if existing

      data = (entry.type == :file) ? write_file(entry.content.b) : nil
      folder.children[name.to_s] = Node.new(entry, data)
    end

    # Writes the tables and the superblock, pads the file system to a
    # whole number of 4 KiB, as the Linux kernel needs, and returns the
    # bytes it wrote.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   squashfs.finish # => 4096
    #--
    # SPDX-SnippetEnd
    #++
    def finish
      flush_fragment
      order = post_order(@root, nil)
      order.each_with_index { |(node, _), index| node.number = index + 1 }
      inodes = Inodes.new(@mtime)
      order.each { |node, parent| inodes.write(node, parent) }
      tables = write_tables(inodes.inode_table, inodes.directory_table)
      used = @io.pos - @base
      @io.write("\0" * (-used % 4096))
      @io.seek(@base)
      @io.write(superblock(order.size, used, tables))
      @io.seek(0, IO::SEEK_END)
      @io.pos - @base
    end

    private def child_folder(node, name, path)
      child = node.children[name]
      if child
        raise Error, "#{path} can't go in #{name}, which is not a folder" unless child.entry.type == :directory

        return child
      end
      node.children[name] = Node.new(Entry.directory(name))
    end

    # Writes a file's full blocks, keeps its tail for a fragment, and
    # returns where both are: <tt>[start, block sizes, fragment, offset,
    # size]</tt>.
    private def write_file(bytes)
      start = @io.pos - @base
      full = bytes.bytesize / BLOCK_SIZE
      sizes = Array.new(full) { |index| write_block(bytes.byteslice(index * BLOCK_SIZE, BLOCK_SIZE).to_s) }
      tail = bytes.byteslice((full * BLOCK_SIZE)..).to_s
      return [start, sizes, nil, 0, bytes.bytesize] if tail.empty?

      flush_fragment if @fragment.bytesize + tail.bytesize > BLOCK_SIZE
      offset = @fragment.bytesize
      @fragment << tail
      [start, sizes, @fragments.size, offset, bytes.bytesize]
    end

    # Writes +block+ compressed, or as it is when that is no larger, and
    # returns its size as an inode records it.
    private def write_block(block)
      compressed = Zlib::Deflate.deflate(block, Zlib::BEST_COMPRESSION)
      if compressed.bytesize < block.bytesize
        @io.write(compressed)
        compressed.bytesize
      else
        @io.write(block)
        block.bytesize | UNCOMPRESSED
      end
    end

    private def flush_fragment
      return if @fragment.empty?

      start = @io.pos - @base
      @fragments << [start, write_block(@fragment)]
      @fragment = "".b
    end

    # Every node with its parent, each folder after what it holds, so a
    # folder's listing can name where each of its children's inodes is.
    private def post_order(node, parent)
      pair = [node, parent] # : [Node, Node?]
      node.children.keys.sort.flat_map { |name| post_order(node.children.fetch(name), node) } << pair
    end

    private def write_tables(inodes, directories)
      inode_table = @io.pos - @base
      @io.write(inodes)
      directory_table = @io.pos - @base
      @io.write(directories)
      fragment_table = @fragments.empty? ? NONE : lookup_table(@fragments.map { |start, size| [start, size, 0].pack("Q<VV") })
      id_table = lookup_table([[0].pack("V")])
      { inode_table:, directory_table:, fragment_table:, id_table: }
    end

    # Writes +records+ as a lookup table, in metadata blocks followed by
    # the list of where each block is, and returns where the list is.
    private def lookup_table(records)
      locations = [] # : Array[Integer]
      bytes = records.join.b
      (0...(bytes.bytesize)).step(METADATA).map { |at| bytes.byteslice(at, METADATA).to_s }.each do |chunk|
        locations << (@io.pos - @base)
        metadata = Metadata.new
        metadata << chunk
        @io.write(metadata.bytes)
      end
      start = @io.pos - @base
      @io.write(locations.pack("Q<*"))
      start
    end

    private def superblock(count, used, tables)
      flags = NO_XATTRS
      [
        MAGIC,
        count,
        @mtime,
        BLOCK_SIZE,
        @fragments.size,
        GZIP,
        17,
        flags,
        1,
        4,
        0,
        @root.reference,
        used,
        tables.fetch(:id_table),
        NONE,
        tables.fetch(:inode_table),
        tables.fetch(:directory_table),
        tables.fetch(:fragment_table),
        NONE,
      ].pack("VVVVVvvvvvvQ<Q<Q<Q<Q<Q<Q<Q<")
    end
  end
end
