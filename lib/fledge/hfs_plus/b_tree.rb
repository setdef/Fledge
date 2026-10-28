# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../error"

module Fledge
  class HfsPlus
    # Writes one of a volume's B-trees (TN1150, "B-Trees"): a header node,
    # then leaf nodes of records in key order, then index nodes above them
    # up to a single root, every node of one size and linked to its
    # neighbors on its level.
    class BTree # :nodoc:
      # A node as it is written: its number, the first key it holds, which
      # the index node above it points with, and its bytes.
      Node = Data.define(:number, :first_key, :bytes)

      # A tree of +size+-byte nodes whose header says its keys are at most
      # +max_key+ bytes, compare as +compare+ says, and have the
      # +attributes+ TN1150's BTHeaderRec defines.
      def initialize(size, max_key:, compare:, attributes:)
        @size = size
        @max_key = max_key
        @compare = compare
        @attributes = attributes
      end

      # A tree with no records: its header node alone.
      def empty
        header_node(depth: 0, root: 0, leaf_records: 0, first_leaf: 0, last_leaf: 0, total: 1)
      end

      # A tree of +records+, each <tt>[key, data]</tt>, sorted as the tree
      # compares its keys.
      def bytes(records)
        leaves = pack_nodes(records.map { |key, data| key + data }, records.map(&:first), kind: -1, height: 1, first: 1)
        levels = [leaves]
        levels << index_level(levels.last, levels.size + 1) until levels.last.size == 1
        nodes = levels.flatten
        header = header_node(depth: levels.size, root: nodes.last.number, leaf_records: records.size,
          first_leaf: leaves.first.number, last_leaf: leaves.last.number, total: nodes.size + 1)
        header + nodes.map(&:bytes).join
      end

      # The index nodes, at +height+, that point to the nodes +below+.
      private def index_level(below, height)
        index = below.map { |node| node.first_key + [node.number].pack("N") }
        pack_nodes(index, below.map(&:first_key), kind: 0, height:, first: below.last.number + 1)
      end

      # Packs +records+ into nodes, numbered from +first+ and linked to
      # each other.
      private def pack_nodes(records, keys, kind:, height:, first:)
        groups = groups(records)
        groups.each_with_index.map do |group, position|
          number = first + position
          forward = (position + 1 < groups.size) ? number + 1 : 0
          backward = position.positive? ? number - 1 : 0
          Node.new(number:, first_key: keys.fetch(group.first), bytes: node(kind, height, forward, backward, group.map { |index| records.fetch(index) }))
        end
      end

      # The indexes of +records+, in groups that each fit in one node with
      # its descriptor and record offsets.
      private def groups(records)
        groups = [] # : Array[Array[Integer]]
        used = 0
        records.each_with_index do |record, index|
          if groups.empty? || 14 + used + record.bytesize + (2 * (groups.last.size + 2)) > @size
            groups << []
            used = 0
          end
          groups.last << index
          used += record.bytesize
        end
        groups
      end

      # A node: its descriptor, its records, free space, and the offsets
      # of its records and of the free space, last first.
      private def node(kind, height, forward, backward, records)
        body = [forward, backward, kind, height, records.size, 0].pack("NNcCnn")
        offsets = [] # : Array[Integer]
        records.each do |record|
          offsets << body.bytesize
          body << record
        end
        offsets << body.bytesize
        body + ("\0" * (@size - body.bytesize - (2 * offsets.size))) + offsets.reverse.pack("n*")
      end

      # The header node: the BTHeaderRec, the user data record, and the
      # map record, which marks the tree's +total+ nodes as used.
      private def header_node(depth:, root:, leaf_records:, first_leaf:, last_leaf:, total:)
        fields = [depth, root, leaf_records, first_leaf, last_leaf, @size, @max_key, total, 0, 0, @size * total, 0, @compare, @attributes]
        header = fields.pack("nNNNNnnNNnNCCN") + ("\0" * 64)
        node(1, 0, 0, 0, [header, "\0" * 128, map(total)])
      end

      # The map record of a header node, its first +total+ bits set.
      private def map(total)
        map = ("\0".b * (@size - 256))
        raise Error, "the volume holds too many files for one catalog map" if total > map.bytesize * 8

        (total / 8).times { |index| map.setbyte(index, 0xFF) }
        map.setbyte(total / 8, (0xFF << (8 - (total % 8))) & 0xFF) unless (total % 8).zero?
        map
      end
    end
  end
end
