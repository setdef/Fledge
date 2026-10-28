# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Fledge
  class HfsPlus
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
  end
end
