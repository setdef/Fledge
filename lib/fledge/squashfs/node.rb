# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class Squashfs
    # An item in the file system, while it is written: the entry it came
    # from, a folder's children by name, where a file's data is, and its
    # inode's number and reference once the inode table is written.
    class Node # :nodoc:
      attr_reader :entry, :children, :data
      attr_accessor :number, :reference

      def initialize(entry, data = nil)
        @entry = entry
        @children = {} # : Hash[String, Node]
        @data = data
        @number = 0
        @reference = 0
      end
    end
  end
end
