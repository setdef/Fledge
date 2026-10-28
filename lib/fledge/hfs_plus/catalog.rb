# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class HfsPlus
    # The records of a volume's catalog (TN1150, "Catalog File"): a folder
    # or file record for each item under its parent's ID and its name, and
    # a thread record under its own ID that finds it again.
    class Catalog # :nodoc:
      # The catalog of +items+, whose names are in +names+ by ID, all made
      # at +date+, in HFS time.
      def initialize(items, names, date)
        @items = items
        @names = names
        @date = date
      end

      # Every record, <tt>[key, record]</tt>, in the order HFSX keeps
      # them: by parent ID, then by name, code unit by code unit.
      def records
        records = [] # : Array[[String, String]]
        @items.each do |item|
          name = @names.fetch(item.id)
          records << [key(item.parent, name), record(item)] << [key(item.id, "".b), thread(item, name)]
        end
        records.sort_by { |key, _| [key.byteslice(2, 4), key.byteslice(8..)] }
      end

      private def key(parent, name)
        [6 + name.bytesize, parent, name.bytesize / 2].pack("nNn") + name
      end

      private def thread(item, name)
        entry = item.entry
        type = (entry.nil? || entry.type == :directory) ? FOLDER_THREAD : FILE_THREAD
        [type, 0, item.parent, name.bytesize / 2].pack("nnNn") + name
      end

      private def record(item)
        entry = item.entry
        return folder_record(item, 0o040755) if entry.nil?
        return folder_record(item, 0o040000 | (entry.mode & 0o7777)) if entry.type == :directory

        file_record(item, entry)
      end

      private def file_record(item, entry)
        symlink = entry.type == :symlink
        mode = symlink ? 0o120755 : 0o100000 | (entry.mode & 0o7777)
        user_info = symlink ? ["slnk", "rhap", 0, 0, 0].pack("a4a4nNn") : "\0" * 16
        start, blocks, size = item.extent || [0, 0, 0]
        [FILE_RECORD, THREAD_EXISTS, 0, item.id, @date, @date, @date, @date, 0].pack("nnNNNNNNN") +
          permissions(mode) + user_info + ("\0" * 16) + [0, 0].pack("NN") +
          HfsPlus.fork_data(start, blocks, size) + HfsPlus.fork_data(0, 0, 0)
      end

      private def folder_record(item, mode)
        [FOLDER_RECORD, HAS_FOLDER_COUNT, item.children, item.id, @date, @date, @date, @date, 0].pack("nnNNNNNNN") +
          permissions(mode) + ("\0" * 32) + [0, item.folders].pack("NN")
      end

      private def permissions(mode)
        [UNKNOWN_OWNER, UNKNOWN_OWNER, 0, 0, mode, 0].pack("NNCCnN")
      end
    end
  end
end
