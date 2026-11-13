# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/adr_digest"

# The ADR digest (rake adr:digest): each ADR's title, problem, drivers,
# and the option it chose, for reading the whole log as a review board
# would.
class AdrDigestTest < Minitest::Test
  ADR = <<~MD
    ---
    status: accepted
    ---

    # ADR 900: Widgets are blue

    ## Context and Problem Statement

    Widgets need a color.

    ## Decision Drivers

    - People like blue.

    ## Considered Options

    1. Blue widgets,
       painted at the factory.
    2. Red widgets.

    ## Decision Outcome

    Chosen: option %s, because people like it.
  MD

  def digest(chosen) = AdrDigest.new(format(ADR, chosen))

  def test_reads_the_title_problem_and_drivers
    adr = digest("1")

    assert_equal "ADR 900: Widgets are blue", adr.title
    assert_equal "Widgets need a color.", adr.context
    assert_equal "- People like blue.", adr.drivers
  end

  def test_reads_an_option_over_several_lines
    assert_equal "Blue widgets, painted at the factory.", digest("1").option(1)
  end

  def test_names_the_chosen_option_by_number
    assert_equal 1, digest("1").chosen
    assert_equal 2, digest("2").chosen
  end

  def test_names_the_chosen_option_by_the_letter_its_item_starts_with
    lettered = format(ADR, "(b)").sub("1. Blue", "1. (b) Blue").sub("2. Red", "2. (a) Red")

    assert_equal 1, AdrDigest.new(lettered).chosen
  end

  def test_prints_the_chosen_option_and_no_other
    text = digest("2").to_s

    assert_includes text, "Chosen, option 2: Red widgets."
    refute_includes text, "Blue widgets"
  end

  def test_says_when_no_option_is_named_as_chosen
    assert_includes AdrDigest.new(format(ADR, "x").sub("option x", "nothing")).to_s, "Chosen: none named"
  end

  def test_says_when_a_section_is_missing
    assert_includes AdrDigest.new("# ADR 901: Bare\n").to_s, "Decision Drivers:\nmissing"
  end
end
