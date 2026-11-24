# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "stringio"
require_relative "../examples/lectern/lib/lectern/text"
require_relative "../examples/lectern/lib/lectern/style"
require_relative "../examples/lectern/lib/lectern/table_layout"
require_relative "../examples/lectern/lib/lectern/pager"

# examples/lectern's parts that need no gem: how text wraps to a width,
# what style the output allows, where a table's columns fall, and the
# pager, which here reads keys from, and draws on, real streams that the
# test makes. The Markdown itself, which needs kramdown and Rouge, is
# read and drawn in test/integration/lectern_test.rb, under the example's
# own bundle.
class LecternTest < Minitest::Test
  def words(text, styles = [])
    text.split(/( )/).map { |part| Lectern::Piece.new(part, styles, (part == " ") ? :space : :word) }
  end

  def wrapped(text, columns)
    Lectern::Text.wrap(words(text), columns).map { |line| line.map(&:text).join }
  end

  def test_text_wraps_at_the_spaces_to_the_width
    assert_equal ["the quick brown", "fox jumps over", "the lazy dog"], wrapped("the quick brown fox jumps over the lazy dog", 15)
  end

  def test_a_word_wider_than_a_line_is_cut_where_the_line_ends
    assert_equal %w[abcd efgh ij], wrapped("abcdefghij", 4)
  end

  def test_words_that_touch_stay_together_across_styles
    pieces = [
      Lectern::Piece.new("fire", [:bold], :word),
      Lectern::Piece.new("fox", [], :word),
      Lectern::Piece.new(" ", [], :space),
      Lectern::Piece.new("runs", [], :word),
]

    assert_equal ["firefox", "runs"], Lectern::Text.wrap(pieces, 8).map { |line| line.map(&:text).join }
  end

  def test_a_break_ends_a_line_wherever_it_falls
    pieces = words("one") + [Lectern::Piece.new("", [], :break)] + words("two")

    assert_equal %w[one two], Lectern::Text.wrap(pieces, 80).map { |line| line.map(&:text).join }
  end

  def test_wide_characters_take_two_columns_and_marks_take_none
    assert_equal 4, Lectern::Text.width("日本")
    assert_equal 1, Lectern::Text.width("é")
    assert_equal ["日本", "語"], wrapped("日本語", 4)
  end

  def test_the_style_follows_the_setting_the_terminal_and_no_color
    choose = -> (setting, terminal, env) { Lectern::Style.choose(setting, terminal:, env:).mode }

    assert_equal :full, choose.call("auto", true, {})
    assert_equal :none, choose.call("auto", false, {})
    assert_equal :none, choose.call("auto", true, { "TERM" => "dumb" })
    assert_equal :attributes, choose.call("auto", true, { "NO_COLOR" => "1" })
    assert_equal :full, choose.call("auto", true, { "NO_COLOR" => "" })
    assert_equal :full, choose.call("always", false, { "NO_COLOR" => "1" })
    assert_equal :none, choose.call("never", true, {})
  end

  def test_painting_leaves_out_what_the_mode_does_not_carry
    assert_equal "\e[1;31mx\e[0m", Lectern::Style.new(:full).paint("x", %i[bold red])
    assert_equal "\e[1mx\e[0m", Lectern::Style.new(:attributes).paint("x", %i[bold red])
    assert_equal "x", Lectern::Style.new(:none).paint("x", %i[bold red])
    assert_equal "x", Lectern::Style.new(:attributes).paint("x", %i[red])
  end

  def test_a_table_takes_the_width_of_its_text_when_it_fits
    rows = [[words("name"), words("size")], [words("lectern"), words("1")]]

    assert_equal [7, 4], Lectern::TableLayout.widths(rows, 80)
  end

  def test_a_table_too_wide_shrinks_its_widest_column_first_and_not_below_a_word
    rows = [[words("id"), words("a long description of the row")], [words("1"), words("short")]]
    widths = Lectern::TableLayout.widths(rows, 20)

    assert_equal 20, widths.sum + (3 * 2) + 1
    assert_equal 2, widths.first
    assert_operator widths.last, :>=, "description".length
  end

  def test_a_row_is_padded_to_its_columns_as_each_alignment_says
    line = Lectern::TableLayout.rows([words("a"), words("b"), words("c")], [3, 3, 3], %i[left right center]).first

    assert_equal ["a  ", "  b", " c "], line.map { |cell| cell.map(&:text).join }
  end

  def test_a_cell_that_wraps_makes_its_row_taller
    lines = Lectern::TableLayout.rows([words("one two"), words("x")], [3, 1], [])

    assert_equal [["one", "x"], ["two", " "]], lines.map { |line| line.map { |cell| cell.map(&:text).join } }
  end

  def pager(keys, lines: (1..10).map { |n| "line #{n}" }, height: 4)
    output = StringIO.new
    Lectern::Pager.new(lines, input: StringIO.new(keys), output:, height:).run
    output.string
  end

  def test_the_pager_shows_a_screen_and_leaves_the_alternate_screen_on_quitting
    shown = pager("q")

    assert shown.start_with?(Lectern::Pager::ENTER)
    assert shown.end_with?(Lectern::Pager::LEAVE)
    assert_includes shown, "line 3"
    refute_includes shown, "line 4"
    assert_includes shown, "lines 1-3 of 10"
  end

  def test_the_pager_moves_by_line_page_and_to_the_ends
    assert_includes pager("jq"), "lines 2-4 of 10"
    assert_includes pager(" q"), "lines 4-6 of 10"
    assert_includes pager("Gq"), "lines 8-10 of 10"
    assert_includes pager("Ggq"), "lines 1-3 of 10"
    assert_includes pager("G kq"), "lines 7-9 of 10"
    assert_includes pager("jjbq"), "lines 1-3 of 10"
  end

  def test_the_pager_does_not_scroll_past_either_end
    assert_includes pager("kq"), "lines 1-3 of 10"
    assert_includes pager("#{' ' * 9}q"), "lines 8-10 of 10"
  end

  def test_the_pager_reads_arrow_keys_and_a_lone_escape_quits
    assert_includes pager("\e[Bq"), "lines 2-4 of 10"
    assert_includes pager("\e[B\e[Aq"), "lines 1-3 of 10"
    assert_includes pager("\e[6~q"), "lines 4-6 of 10"
    assert_includes pager("\u0000Pq"), "lines 2-4 of 10"
    assert_includes pager("\u00E0Q\u00E0Iq"), "lines 1-3 of 10"
    assert pager("\e").end_with?(Lectern::Pager::LEAVE)
  end

  def test_the_pager_quits_where_the_input_ends
    assert pager("").end_with?(Lectern::Pager::LEAVE)
  end
end
