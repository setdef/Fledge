# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0

# Basket's screen, tested on the phone: these tests make the screen's
# real widgets, UIKit's on iOS and Android's views on Android, so they
# run only inside the app, where fledge test runs test/phone.rb:
#
#   fledge test ios test/phone.rb
#   fledge test android test/phone.rb

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../lib/basket/list"

# What both phones' tests share: a list in a folder of its own.
module ScreenTesting
  # A list's file in a folder of the test's own.
  def setup
    @dir = Dir.mktmpdir
    @list = Basket::List.new(File.join(@dir, "basket.json"))
  end

  # Deletes the test's folder.
  def teardown
    FileUtils.rm_rf(@dir)
  end
end

if $LOAD_PATH.resolve_feature_path("fledge/objc")
  require_relative "../lib/basket/ios"

  # The tests of Basket::IOS::Screen, with UIKit's own views.
  class IOSScreenTest < Minitest::Test
    include ScreenTesting

    # The list shows a row for each of its items.
    def test_it_shows_a_row_for_each_item
      %w[Milk Eggs].each { |item| @list.add(item) }

      assert_equal 2, Basket::IOS::Screen.new(@list).rows
    end

    # Adding takes what the field holds into the list and a row, and
    # empties the field.
    def test_adding_puts_what_the_field_holds_in_the_list_and_empties_the_field
      screen = Basket::IOS::Screen.new(@list)
      screen.field.text = "Milk"
      screen.add

      assert_equal ["Milk"], @list.items
      assert_equal 1, screen.rows
      assert_equal "", screen.field.text.to_s
    end
  end
elsif $LOAD_PATH.resolve_feature_path("fledge/jni")
  require_relative "../lib/basket/android"

  # The tests of Basket::Android::Screen, with Android's own views.
  class AndroidScreenTest < Minitest::Test
    include ScreenTesting

    # The screen of the test's list, drawn on the app's activity.
    def screen
      Basket::Android::Screen.new(Fledge::JNI.import("org.setdef.fledge.FledgeRuby").activity, @list)
    end

    # The list shows a row for each of its items.
    def test_it_shows_a_row_for_each_item
      %w[Milk Eggs].each { |item| @list.add(item) }

      assert_equal 2, screen.rows
    end

    # Adding takes what the field holds into the list and a row, and
    # empties the field.
    def test_adding_puts_what_the_field_holds_in_the_list_and_empties_the_field
      shown = screen
      shown.field.setText("Milk")
      shown.add

      assert_equal ["Milk"], @list.items
      assert_equal 1, shown.rows
      assert_equal "", shown.field.getText.to_s
    end

    # Taking an item out takes its row away.
    def test_removing_takes_the_row_away
      %w[Milk Eggs].each { |item| @list.add(item) }
      shown = screen
      shown.remove(0)

      assert_equal ["Eggs"], @list.items
      assert_equal 1, shown.rows
    end
  end
end
