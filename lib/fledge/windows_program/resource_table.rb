# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class WindowsProgram
    # Writes a resource section: the three levels of directories Windows
    # searches (type, name, language), then the names, the data entries,
    # and the data, each piece aligned as the PE specification asks.
    #
    # The directories go breadth first, as Microsoft's resource compiler
    # writes them, so an entry's subdirectory is always the next one not
    # yet pointed to, and a language's data entry the next data entry.
    class ResourceTable # :nodoc:
      # One directory: its keys, in the order Windows searches them, and
      # what each holds, a directory one level down or a resource's data.
      Directory = Data.define(:keys, :children) do
        # The directory of +hash+'s keys, sorted, each holding what the
        # block makes of its value.
        def self.of(hash)
          keys = ResourceTable.sorted(hash.keys)
          new(keys:, children: keys.map { |key| yield hash.fetch(key) })
        end
      end

      # The keys of a directory in the order Windows' binary search through
      # it expects: names first, case-insensitively, then IDs.
      def self.sorted(keys)
        names, ids = keys.partition { |key| key.is_a?(String) }
        [*names.sort_by { |name| name.to_s.upcase }, *ids.sort_by(&:to_i)]
      end

      def initialize(resources)
        tree = {} # : Hash[key, Hash[key, Hash[key, String]]]
        resources.each do |(type, name, language), data|
          ((tree[type] ||= {})[name] ||= {})[language] = data
        end
        @root = Directory.of(tree) do |names|
          Directory.of(names) { |languages| Directory.of(languages) { |data| data } }
        end
      end

      # The section's bytes, for a section at virtual address +address+.
      def bytes(address)
        directories = breadth_first
        offsets = directory_offsets(directories)
        strings, string_offsets = name_strings(directories.flat_map(&:keys), offsets.last)
        entries_at = align(offsets.last + strings.bytesize, 4)
        leaves = directories.flat_map { |directory| strings_in(directory.children) }
        placed = data_offsets(leaves, entries_at + (leaves.size * 16))
        pointers = targets(directories, offsets, entries_at)
        out = directories.each_with_index.map do |directory, index|
          directory_bytes(directory.keys, string_offsets, pointers.fetch(index))
        end.join
        out = (out << strings).ljust(entries_at, "\0")
        leaves.each_with_index { |data, index| out << [address + placed.fetch(index), data.bytesize, 0, 0].pack("V4") }
        leaves.each_with_index { |data, index| out = out.ljust(placed.fetch(index), "\0") << data }
        out
      end

      # Every directory, the root first, then each level's in turn.
      private def breadth_first
        order = [@root]
        index = 0
        while (directory = order[index])
          directory.children.each { |child| order << child if child.is_a?(Directory) }
          index += 1
        end
        order
      end

      # Where each directory begins, and, last, where the names after them
      # begin.
      private def directory_offsets(directories)
        directories.each_with_object([0]) { |directory, offsets| offsets << (offsets.last + 16 + (directory.keys.size * 8)) }
      end

      # What each entry of each directory points to: its subdirectory,
      # flagged as one, or its data entry.
      private def targets(directories, offsets, entries_at)
        next_directory = 0
        next_leaf = -1
        directories.map do |directory|
          directory.children.map do |child|
            child.is_a?(Directory) ? (0x8000_0000 | offsets.fetch(next_directory += 1)) : entries_at + ((next_leaf += 1) * 16)
          end
        end
      end

      # Where each of +leaves+ goes, from +at+, each aligned to 8 bytes.
      private def data_offsets(leaves, at)
        leaves.map do |data|
          start = align(at, 8)
          at = start + data.bytesize
          start
        end
      end

      # The names among +keys+, each as a length and UTF-16 characters,
      # from +at+, and where each one is.
      private def name_strings(keys, at)
        strings = +"".b
        offsets = {} # : Hash[String, Integer]
        strings_in(keys).uniq.each do |name|
          offsets[name] = at + strings.bytesize
          utf16 = name.encode(Encoding::UTF_16LE).b
          strings << [utf16.bytesize / 2].pack("v") << utf16
        end
        [strings, offsets]
      end

      # A directory of +keys+, each pointing where +pointers+ says.
      private def directory_bytes(keys, string_offsets, pointers)
        named = keys.count { |key| key.is_a?(String) }
        header = [0, 0, 0, 0, named, keys.size - named].pack("V2v4")
        header + keys.each_with_index.map do |key, index|
          name = key.is_a?(String) ? (0x8000_0000 | string_offsets.fetch(key)) : key
          [name, pointers.fetch(index)].pack("V2")
        end.join
      end

      # The Strings among +values+.
      private def strings_in(values)
        found = [] # : Array[String]
        values.each do |value|
          case value
          when String then found << value
          end
        end
        found
      end

      private def align(value, alignment)
        ((value + alignment - 1) / alignment) * alignment
      end
    end
  end
end
