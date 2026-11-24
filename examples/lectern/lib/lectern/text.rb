# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

module Lectern
  # A run of text with the styles it is drawn in, and what it is to the
  # line breaker: a +:word+, which never breaks, a +:space+, where a line
  # may break, or a +:break+, which always does.
  class Piece < Data.define(:text, :styles, :kind)
    # The columns the text takes on a terminal.
    def width
      Text.width(text)
    end
  end

  # Measuring, cutting, and wrapping text for a terminal's columns.
  module Text
    # The code points a terminal draws two columns wide: Hangul Jamo, CJK,
    # kana, and fullwidth forms, and emoji.
    WIDE = [
      0x1100..0x115F,
      0x2E80..0xA4CF,
      0xAC00..0xD7A3,
      0xF900..0xFAFF,
      0xFE30..0xFE6F,
      0xFF00..0xFF60,
      0xFFE0..0xFFE6,
      0x1F300..0x1F64F,
      0x1F900..0x1F9FF,
      0x20000..0x3FFFD,
    ].freeze
    # Marks and joiners, which take no column of their own.
    ZERO = /\p{Mn}|\p{Me}|\p{Cf}/

    # The columns +string+ takes: two for a wide character, none for a
    # combining mark. This is wcwidth's rule, not its table.
    def self.width(string)
      string.each_char.sum { |char| char_width(char) }
    end

    # The columns of one character.
    def self.char_width(char)
      return 0 if char.match?(ZERO)

      (WIDE.any? { |range| range.cover?(char.ord) }) ? 2 : 1
    end

    # +string+ cut in two, the first part at most +columns+ wide.
    def self.cut(string, columns)
      used = 0
      string.each_char.with_index do |char, index|
        used += char_width(char)
        return [string[0, index], string[index..]] if used > columns && index.positive?
      end
      [string, ""]
    end

    # +pieces+ broken into lines at most +columns+ wide, at the spaces. A
    # word wider than a line is cut where the line ends.
    def self.wrap(pieces, columns)
      columns = [columns, 1].max
      lines = [[]]
      used = 0
      pending = nil
      units(pieces).each do |unit|
        case unit
        in :break
          lines << []
          used = 0
          pending = nil
        in Piece => space
          pending = space unless lines.last.empty?
        in Array => word
          used, pending = place(word, lines, used, pending, columns)
        end
      end
      lines.pop while lines.size > 1 && lines.last.empty?
      lines
    end

    # Puts +word+ on the last of +lines+, or on a new one when it does not
    # fit, and returns the columns that line now uses.
    def self.place(word, lines, used, pending, columns)
      size = word.sum(&:width)
      if lines.last.empty?
        pending = nil
      elsif used + 1 + size <= columns
        lines.last << pending if pending
        used += pending ? 1 : 0
        pending = nil
      else
        lines << []
        used = 0
        pending = nil
      end
      pieces = (size > columns) ? hard(word, columns) : [word]
      pieces.each_with_index do |part, index|
        if index.positive?
          lines << []
          used = 0
        end
        lines.last.concat(part)
        used += part.sum(&:width)
      end
      [used, pending]
    end

    # +pieces+ cut into lines of exactly +columns+ wide, but the last,
    # wherever the cut falls.
    def self.hard(pieces, columns)
      lines = [[]]
      used = 0
      pieces.each do |piece|
        text = piece.text
        until text.empty?
          if used >= columns
            lines << []
            used = 0
          end
          head, text = cut(text, columns - used)
          lines.last << piece.with(text: head)
          used += Text.width(head)
        end
      end
      lines
    end

    # The words, as arrays of the pieces that touch, with the spaces and
    # breaks between them.
    def self.units(pieces)
      pieces.chunk_while { |a, b| a.kind == :word && b.kind == :word }.map do |group|
        case group.first.kind
        when :word then group
        when :break then :break
        else group.first
        end
      end
    end
    private_class_method :units
  end
end
