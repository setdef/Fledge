# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket's screen on each system, made of the real widgets: AppKit's on a
# Mac, which these tests make and drive without showing a window, so they
# run as any Ruby test does:
#
#   ruby test/screen_test.rb
#
# and UIKit's on iOS and Android's views on Android, which run only
# inside the app, where fledge test runs test/phone.rb:
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

# Whether this Ruby runs on an iPhone or iPad, as main.rb asks.
ON_IOS = RUBY_PLATFORM.include?("darwin") && begin
  require_relative "../lib/basket/objc"
  Basket::ObjC.load_framework("UIKit")
end

# Whether this Ruby runs on a Mac, with AppKit to draw with.
ON_MAC = RUBY_PLATFORM.include?("darwin") && !ON_IOS && Basket::ObjC.load_framework("AppKit")

if ON_MAC
  require_relative "../lib/basket/macos"

  # The tests of Basket::MacOS::Screen, with AppKit's views, driven
  # as a person drives them: the Add button and the menu items are pressed
  # with the messages AppKit sends when they are clicked, and a key is
  # typed with the event AppKit makes for it. No window is shown.
  class MacOSScreenTest < Minitest::Test
    include ScreenTesting

    # AppKit's constants these tests pass.
    # NSEventTypeKeyDown
    KEY_DOWN = 10
    # NSDeleteCharacter, which the Delete key types
    DELETE = "\u007f"

    # The app, which AppKit needs before it makes a view.
    def setup
      super
      @app = Basket::ObjC::NSApplication.sharedApplication
    end

    # The screen of the test's list, with its menu bar installed.
    def screen
      @screen ||= Basket::MacOS::Screen.new(@list).tap do |shown|
        @app.mainMenu, = Basket::MacOS::Menus.bar(shown.actions)
      end
    end

    # Selects the row at +index+ of the screen's table, as a click does.
    def select_row(index)
      indexes = Basket::ObjC::NSIndexSet.indexSetWithIndex(index)
      screen.table.selectRowIndexes(indexes, byExtendingSelection: false)
    end

    # The item +name+ of the main menu's menu +title+.
    def menu_item(title, name)
      screen
      holder = @app.mainMenu.itemArray.to_a.find { |item| item.title.to_s == title }
      holder.submenu.itemArray.to_a.find { |item| item.title.to_s == name }
    end

    # Chooses +item+ from its menu, as a click on it does.
    def choose(item)
      menu = item.menu
      capture_io { menu.performActionForItemAtIndex(menu.indexOfItem(item)) }
    end

    # The key event for typing +characters+ with +flags+.
    def key_event(characters, flags = 0)
      Basket::ObjC::NSEvent.keyEventWithType(KEY_DOWN, location: [0.0, 0.0], modifierFlags: flags, timestamp: 0.0,
        windowNumber: screen.window.windowNumber, context: nil, characters:,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 51)
    end

    # The list shows a row for each of its items, each in a table cell view.
    def test_it_shows_a_row_for_each_item_in_a_table_cell_view
      %w[Milk Eggs].each { |item| @list.add(item) }
      cell = screen.table.viewAtColumn(0, row: 1, makeIfNecessary: true)

      assert_equal 2, screen.rows
      assert_equal "NSTableCellView", cell.class.objc_name
      assert_equal "Eggs", cell.textField.stringValue.to_s
    end

    # Pressing Add takes what the field holds into the list and a row,
    # and empties the field.
    def test_adding_puts_what_the_field_holds_in_the_list_and_empties_the_field
      screen.field.stringValue = "Milk"
      screen.button.performClick(nil)

      assert_equal ["Milk"], @list.items
      assert_equal 1, screen.rows
      assert_equal "", screen.field.stringValue.to_s
    end

    # Add is the window's default button, which Return presses.
    def test_add_is_the_default_button
      assert_equal "\r", screen.button.keyEquivalent.to_s
    end

    # An empty field adds nothing.
    def test_adding_nothing_adds_nothing
      screen.field.stringValue = "  "
      screen.button.performClick(nil)

      assert_empty @list.items
      assert_equal 0, screen.rows
    end

    # Edit > Delete takes the selected row away.
    def test_the_edit_menus_delete_removes_the_selected_row
      %w[Milk Eggs].each { |item| @list.add(item) }
      select_row(0)
      out, = choose(menu_item("Edit", "Delete"))

      assert_equal ["Eggs"], @list.items
      assert_equal 1, screen.rows
      assert_includes out, "Basket removed Milk"
    end

    # Delete is off while no row is selected, and on when one is.
    def test_delete_is_on_only_while_a_row_is_selected
      @list.add("Milk")
      item = menu_item("Edit", "Delete")

      refute screen.actions.validateMenuItem(item)
      select_row(0)

      assert screen.actions.validateMenuItem(item)
    end

    # Command-Delete is Edit > Delete's key equivalent.
    def test_command_delete_removes_the_selected_row
      @list.add("Milk")
      select_row(0)
      handled = nil
      capture_io { handled = @app.mainMenu.performKeyEquivalent(key_event("\b", Basket::MacOS::COMMAND)) }

      assert handled
      assert_empty @list.items
    end

    # The row's context menu has Delete.
    def test_the_context_menu_deletes_the_selected_row
      %w[Milk Eggs].each { |item| @list.add(item) }
      select_row(1)
      menu = screen.table.menu
      choose(menu.itemAtIndex(0))

      assert_equal "Delete", menu.itemAtIndex(0).title.to_s
      assert_equal ["Milk"], @list.items
    end

    # The Delete key, which AppKit hands the table as deleteBackward:,
    # takes the selected row away.
    def test_the_delete_key_removes_the_selected_row
      %w[Milk Eggs].each { |item| @list.add(item) }
      select_row(1)
      capture_io { screen.table.interpretKeyEvents([key_event(DELETE)]) }

      assert_equal ["Milk"], @list.items
      assert_equal 1, screen.rows
    end

    # The menu bar has the menus Apple's guidelines list, in order, and
    # Edit has what the text field needs.
    def test_the_menu_bar_has_the_menus_the_guidelines_list
      menu_item("Edit", "Delete")

      assert_equal %w[Basket File Edit Window], @app.mainMenu.itemArray.to_a.map { |item| item.title.to_s }
      %w[Cut Copy Paste Select\ All].each { |name| refute_nil menu_item("Edit", name), "Edit has no #{name}" }
      refute_nil menu_item("Basket", "Quit Basket")
    end
  end
elsif ON_IOS
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
elsif RUBY_PLATFORM.include?("android")
  require_relative "../lib/basket/android"

  # The tests of Basket::Android::Screen, with Android's own views.
  class AndroidScreenTest < Minitest::Test
    include ScreenTesting

    # The screen of the test's list, drawn on the app's activity.
    def screen
      Basket::Android::Screen.new(Basket::Android::Activities.first, @list)
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

unless RUBY_PLATFORM.include?("darwin") || RUBY_PLATFORM.include?("android")
  # Basket's Mac screen, which only a Mac can draw, so that a run on a
  # computer of another system says it did not run it.
  class MacOSScreenTest < Minitest::Test
    # Skips, naming AppKit, which a Mac has.
    def test_the_mac_screen
      skip "AppKit is a Mac's, so Basket's Mac screen runs only there"
    end
  end
end
