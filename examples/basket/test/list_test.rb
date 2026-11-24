# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0

# Basket's list, tested with Minitest as any Ruby is: ruby
# test/list_test.rb on your own computer, and inside the app on a phone,
# where test/phone.rb runs it with the tests of the screen.

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../lib/basket/list"

# The tests of Basket::List.
class ListTest < Minitest::Test
  # A list's file in a folder of the test's own.
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "basket.json")
  end

  # Deletes the test's folder.
  def teardown
    FileUtils.rm_rf(@dir)
  end

  # A list with no file yet has no items.
  def test_a_new_list_is_empty
    assert_empty Basket::List.new(@path).items
  end

  # An item keeps no spaces a person typed around it.
  def test_it_adds_an_item_without_the_spaces_around_it
    list = Basket::List.new(@path)
    list.add("  Milk ")

    assert_equal ["Milk"], list.items
  end

  # Text of spaces alone makes no item.
  def test_it_adds_nothing_for_blank_text
    list = Basket::List.new(@path)
    list.add("   ")

    assert_empty list.items
  end

  # Taking an item out leaves the others in their order.
  def test_it_removes_the_item_at_a_place
    list = Basket::List.new(@path)
    %w[Milk Eggs Bread].each { |item| list.add(item) }
    list.remove(1)

    assert_equal %w[Milk Bread], list.items
  end

  # Each change is saved, so a list read again has it.
  def test_its_items_are_there_when_the_app_starts_again
    Basket::List.new(@path).add("Milk")

    assert_equal ["Milk"], Basket::List.new(@path).items
  end
end
