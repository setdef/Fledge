# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class Squashfs
    # Writes the inode table and the directory table: an inode for each
    # node, and for each folder a listing of its children that names
    # where each child's inode is. A folder's inode records where its
    # listing is, so the nodes come children first.
    class Inodes # :nodoc:
      # Tables whose inodes say everything was made at +mtime+.
      def initialize(mtime)
        @mtime = mtime
        @inodes = Metadata.new
        @directories = Metadata.new
      end

      # The inode table's bytes, once every node is written.
      def inode_table
        @inodes.bytes
      end

      # The directory table's bytes, once every node is written.
      def directory_table
        @directories.bytes
      end

      # Writes +node+'s inode, and its listing if it is a folder, whose
      # parent is +parent+ (+nil+ for the root): after every node it holds.
      def write(node, parent)
        entry = node.entry
        node.reference = @inodes.reference
        permissions = (entry.type == :symlink) ? 0o777 : entry.mode & 0o7777
        case entry.type
        when :directory then write_directory(node, parent, permissions)
        when :symlink then @inodes << header(SYMLINK, permissions, node) << [1, entry.link.bytesize].pack("VV") << entry.link.b
        else write_file(node, permissions)
        end
      end

      # A file's inode: where its blocks begin, its fragment, its size, and
      # each block's size.
      private def write_file(node, permissions)
        start, sizes, fragment, offset, size = node.data || [0, [], nil, 0, 0]
        @inodes << header(FILE, permissions, node) <<
          [start, fragment || 0xFFFF_FFFF, offset, size].pack("VVVV") << sizes.pack("V*")
      end

      private def write_directory(node, parent, permissions)
        block, offset = @directories.position
        listing = listing(node)
        @directories << listing
        links = 2 + node.children.values.count { |child| child.entry.type == :directory }
        parent_number = parent ? parent.number : 0
        if listing.bytesize + 3 < 0x10000
          @inodes << header(DIRECTORY, permissions, node) << [block, links, listing.bytesize + 3, offset, parent_number].pack("VVvvV")
        else
          @inodes << header(EXTENDED_DIRECTORY, permissions, node) <<
            [links, listing.bytesize + 3, block, parent_number, 0, offset, 0xFFFF_FFFF].pack("VVVVvvV")
        end
      end

      # A folder's listing in the directory table: runs of entries, each led
      # by a header naming the metadata block their inodes are in.
      private def listing(node)
        out = "".b
        run = [] # : Array[[String, Node]]
        node.children.keys.sort.each do |name|
          child = node.children.fetch(name)
          if run.any? && (run.size == RUN || block_of(run.first.last) != block_of(child) ||
              (child.number - run.first.last.number).abs > 32_767)

            out << run_bytes(run)
            run = []
          end
          run << [name, child]
        end
        out << run_bytes(run) unless run.empty?
        out
      end

      private def block_of(node)
        node.reference >> 16
      end

      private def run_bytes(run)
        first = run.first.last
        out = [run.size - 1, block_of(first), first.number].pack("VVV")
        run.each do |name, child|
          type = { directory: DIRECTORY, file: FILE, symlink: SYMLINK }.fetch(child.entry.type)
          out << [child.reference & 0xFFFF, child.number - first.number, type, name.bytesize - 1].pack("vs<vv") << name.b
        end
        out
      end

      private def header(type, permissions, node)
        [type, permissions, 0, 0, @mtime, node.number].pack("vvvvVV")
      end

      # Writes the inode, directory, fragment, and ID tables, and returns
      # their offsets.
    end
  end
end
