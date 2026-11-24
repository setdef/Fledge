# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "text"

module Lectern
  # Where a table's columns fall, and what each row looks like in them.
  module TableLayout
    # The least a column shrinks to when its words are wider than the room.
    NARROWEST = 3

    # The width of each column of +rows+ (rows of cells, each a list of
    # pieces), so that the table, with a border and a space each side of
    # every column, fits in +total+ columns: as wide as its text, or
    # narrower, taking from the widest column first, and not below its
    # longest word until nothing else is left to take from.
    def self.widths(rows, total)
      count = rows.map(&:size).max || 0
      natural = (0...count).map { |index| rows.map { |row| cell_width(row[index]) }.max }
      longest = (0...count).map { |index| rows.map { |row| longest_word(row[index]) }.max }
      room = total - (3 * count) - 1
      widths = natural.map { |width| [width, 1].max }
      [longest, [NARROWEST] * count].each do |floors|
        shrink(widths, floors, room)
      end
      widths
    end

    # The lines of one table +row+ in columns of +widths+: each line a list
    # of one list of pieces per column, padded to its column as the
    # +alignments+ (:left, :right, :center, or :default) say.
    def self.rows(row, widths, alignments)
      cells = widths.each_index.map { |index| Text.wrap(row[index] || [], widths[index]) }
      height = cells.map(&:size).max
      (0...height).map do |line|
        widths.each_index.map { |index| pad(cells[index][line] || [], widths[index], alignments[index]) }
      end
    end

    # Takes from the widest column that is wider than its floor, one
    # column at a time, until +widths+ add up to +room+ or no column can.
    def self.shrink(widths, floors, room)
      while widths.sum > room
        index = widths.each_index.select { |i| widths[i] > floors[i] }.max_by { |i| widths[i] }
        break unless index

        widths[index] -= 1
      end
    end

    # +pieces+ with spaces on the side +alignment+ puts them, to +width+.
    def self.pad(pieces, width, alignment)
      gap = width - pieces.sum(&:width)
      return pieces if gap <= 0

      spaces = -> (count) { count.zero? ? [] : [Piece.new(" " * count, [], :space)] }
      case alignment
      when :right then spaces.call(gap) + pieces
      when :center then spaces.call(gap / 2) + pieces + spaces.call(gap - (gap / 2))
      else pieces + spaces.call(gap)
      end
    end

    def self.cell_width(pieces)
      (pieces || []).reject { |piece| piece.kind == :break }.sum(&:width)
    end

    def self.longest_word(pieces)
      (pieces || []).chunk_while { |a, b| a.kind == :word && b.kind == :word }
        .map { |group| (group.first.kind == :word) ? group.sum(&:width) : 0 }.max || 0
    end

    private_class_method :shrink, :pad, :cell_width, :longest_word
  end
end
