# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket's screen on Windows (lib/basket/windows.rb), tested through its
# real window and controls: each test posts a person's typing, clicks, and
# keys to the window, runs its message loop until they are handled, and
# reads what the list and the rows then hold. It runs as any Ruby test
# does, on Windows:
#
#   ruby test/windows_test.rb
#
# and each test says why it does not run where it cannot.

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../lib/basket/list"

# Why these tests cannot run on this computer, or nil when they can: the
# screen is Win32's, and Win32 needs Windows and fiddle, which Bundler
# hides until a Gemfile lists it.
WINDOWS_UNAVAILABLE = if Gem.win_platform?
  begin
    require_relative "../lib/basket/windows"
    nil
  rescue LoadError => e
    e.message
  end
else
  "Basket's Windows screen draws with Win32, which only Windows has"
end

# The tests of Basket::Windows::Screen, with Win32's controls.
class WindowsScreenTest < Minitest::Test
  # WM_COMMAND
  COMMAND = 0x111
  # WM_KEYDOWN
  KEY_DOWN = 0x100
  # WM_CHAR
  CHAR = 0x102
  # BM_CLICK
  CLICK = 0xF5
  # VK_RETURN
  RETURN_KEY = 0x0D
  # The id of the command each test posts last, which ends the message loop.
  DONE = 9999

  # The screen every test but one uses, made when a test first asks.
  # On Windows 11 (build 10.0.26300), a process's third window and each
  # one after it take two seconds to be shown, or to be given the
  # keyboard, which Add does; the first two do not. A window for each
  # test would make most of them wait, so one window serves them all,
  # and the test that needs another makes the second, and never gives it
  # the keyboard. The window and its folder go when the last test has run.
  def self.shared
    @shared ||= begin
      dir = Dir.mktmpdir
      list = Basket::List.new(File.join(dir, "basket.json"))
      screen = Basket::Windows::Screen.new(list)
      screen.window.on_command(DONE) { Basket::Win32::Functions::POST_QUIT.call(0) }
      Minitest.after_run do
        close(screen)
        FileUtils.rm_rf(dir)
      end
      [list, screen]
    end
  end

  # Closes the window of +screen+, which ends its message loop.
  def self.close(screen)
    screen.window.close
    Basket::Win32.run(screen.window)
  end

  # The shared screen, with no items and nothing typed.
  def setup
    skip WINDOWS_UNAVAILABLE if WINDOWS_UNAVAILABLE

    @list, @screen = self.class.shared
    @list.remove(0) until @list.items.empty?
    @screen.table.remove(0) until @screen.rows.zero?
    @screen.field.text = ""
  end

  # The shared screen after it takes +items+, as they would be had the
  # person added them.
  def open_screen(*items)
    items.each do |item|
      @list.add(item)
      @screen.table.add(item)
    end
    @screen
  end

  # Types +text+ into the field, one character at a time.
  def type(text)
    text.each_char { |character| post(@screen.field, CHAR, character.ord) }
  end

  # Posts a message to a control.
  def post(control, message, word = 0)
    Basket::Win32::Functions::POST_MESSAGE.call(control.handle, message, word, 0)
  end

  # Handles every message posted so far.
  def settle
    Basket::Win32::Functions::POST_MESSAGE.call(@screen.window.handle, COMMAND, DONE, 0)
    Basket::Win32.run(@screen.window)
  end

  # The list shows a row for each of its items.
  def test_it_shows_a_row_for_each_item
    dir = Dir.mktmpdir
    list = Basket::List.new(File.join(dir, "basket.json"))
    list.add("Milk")
    list.add("Eggs")
    screen = Basket::Windows::Screen.new(list)

    assert_equal 2, screen.rows
  ensure
    self.class.close(screen) if screen
    FileUtils.rm_rf(dir)
  end

  # A click on Add takes what the field holds into the list and a row,
  # and empties the field.
  def test_adding_puts_what_the_field_holds_in_the_list_and_empties_the_field
    open_screen
    type("Milk")
    post(@screen.add_button, CLICK)
    settle

    assert_equal ["Milk"], @list.items
    assert_equal 1, @screen.rows
    assert_equal "", @screen.field.text
  end

  # Return is Add's, the window's default button, wherever the person is
  # typing.
  def test_return_in_the_field_adds
    open_screen
    type("Eggs")
    post(@screen.field, KEY_DOWN, RETURN_KEY)
    settle

    assert_equal ["Eggs"], @list.items
    assert_equal 1, @screen.rows
  end

  # A field with only spaces adds nothing.
  def test_adding_nothing_adds_nothing
    open_screen
    type("  ")
    post(@screen.add_button, CLICK)
    settle

    assert_empty @list.items
    assert_equal 0, @screen.rows
  end

  # Remove takes the selected item out of the list and its row away.
  def test_removing_takes_the_selected_item_and_its_row_away
    open_screen("Milk", "Eggs").select(0)
    post(@screen.remove_button, CLICK)
    settle

    assert_equal ["Eggs"], @list.items
    assert_equal 1, @screen.rows
  end

  # Delete, pressed in the list, removes the selected row as Remove does.
  def test_delete_in_the_list_removes_the_selected_item
    open_screen("Milk", "Eggs").select(1)
    post(@screen.table, KEY_DOWN, Basket::Windows::DELETE_KEY)
    settle

    assert_equal ["Milk"], @list.items
    assert_equal 1, @screen.rows
  end

  # The controls are Common Controls 6's: only they take a text field's
  # cue, which Windows 11's controls show.
  def test_the_controls_are_common_controls_six
    open_screen
    # EM_SETCUEBANNER
    assert_equal 1, @screen.field.send_message(0x1501, 1, Basket::Win32.wide("Add an item").to_i)
  end
end
