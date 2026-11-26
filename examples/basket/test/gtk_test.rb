# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket's bridge to GTK 4 and libadwaita (lib/basket/gtk.rb) and its
# screen on Linux (lib/basket/linux.rb), whose tests call the real libraries:
# the bridge needs only that this computer has them, and the screen needs
# a display to draw on as well. Each test says why it does not run where
# it cannot, so a developer without GTK 4 sees a skip and not a failure:
#
#   ruby test/gtk_test.rb
#
# and under Xvfb on a computer with no screen:
#
#   xvfb-run -a ruby test/gtk_test.rb

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../lib/basket/list"

# Why these tests cannot run on this computer, or nil when they can.
UNAVAILABLE = begin
  require_relative "../lib/basket/gtk"
  Basket::GTK.load && nil
rescue LoadError => e
  e.message
end

# Why the screen's tests cannot run on this computer, or nil when they can.
NO_DISPLAY = if UNAVAILABLE
  UNAVAILABLE
elsif ENV.values_at("DISPLAY", "WAYLAND_DISPLAY").none?
  "neither DISPLAY nor WAYLAND_DISPLAY names a display, and GTK exits when it cannot open one"
end

# The bridge: every function it declares is in the libraries.
class GTKBridgeTest < Minitest::Test
  # Each prototype declares a function the two libraries have, which a
  # GTK 4 or libadwaita too old for the screen would lack.
  def test_every_declared_function_is_in_the_libraries
    skip UNAVAILABLE if UNAVAILABLE

    Basket::GTK::PROTOTYPES.each_line do |prototype|
      name = prototype[/\A\w+/]

      assert_respond_to Basket::GTK, name, "#{name} is not callable"
    end
  end

  # A function GTK does not declare is an error as any missing method is.
  def test_a_function_that_is_not_declared_is_not_callable
    skip UNAVAILABLE if UNAVAILABLE

    assert_raises(NoMethodError) { Basket::GTK.gtk_no_such_function }
  end
end

# The screen's tests, with GTK's widgets.
class LinuxScreenTest < Minitest::Test
  # A list in a folder made for the test.
  def setup
    skip NO_DISPLAY if NO_DISPLAY

    require_relative "../lib/basket/linux"
    Basket::GTK.adw_init
    @dir = Dir.mktmpdir
    @list = Basket::List.new(File.join(@dir, "basket.json"))
  end

  # Deletes the test's folder.
  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  # The screen of the test's list, in a window of an application that
  # never runs, which is registered, as running one does before it
  # sends the signal that makes the screen.
  def screen
    application = Basket::GTK.adw_application_new("com.setdef.fledge.BasketTest", 0)
    register = Fiddle::Function.new(Fiddle.dlopen("libgtk-4.so.1")["g_application_register"],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    register.call(application, nil, nil)
    Basket::Linux::Screen.new(application, @list)
  end

  # Emits +signal+ of +instance+, as GTK does for a person's input.
  def emit(instance, signal)
    emit = Fiddle::Function.new(Fiddle.dlopen("libgtk-4.so.1")["g_signal_emit_by_name"],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VARIADIC], Fiddle::TYPE_VOID)
    emit.call(instance, signal)
  end

  # The list shows a row for each of its items.
  def test_it_shows_a_row_for_each_item
    %w[Milk Eggs].each { |item| @list.add(item) }

    assert_equal 2, screen.rows
  end

  # Return in the entry takes what it holds into the list and a row, and
  # empties the entry.
  def test_return_adds_what_the_entry_holds_and_empties_the_entry
    shown = screen
    Basket::GTK.gtk_editable_set_text(shown.entry, "Milk")
    emit(shown.entry, "activate")

    assert_equal ["Milk"], @list.items
    assert_equal 1, shown.rows
    assert_equal "", Basket::GTK.gtk_editable_get_text(shown.entry)
  end

  # An entry with nothing but spaces adds nothing.
  def test_an_empty_entry_adds_nothing
    shown = screen
    Basket::GTK.gtk_editable_set_text(shown.entry, "  ")
    shown.add

    assert_empty @list.items
    assert_equal 0, shown.rows
  end

  # Taking an item out takes its row away.
  def test_removing_takes_the_row_away
    %w[Milk Eggs].each { |item| @list.add(item) }
    shown = screen
    shown.remove(shown.row(0))

    assert_equal ["Eggs"], @list.items
    assert_equal 1, shown.rows
  end
end
