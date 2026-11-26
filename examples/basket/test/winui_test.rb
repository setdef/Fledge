# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket's screen on Windows with the Windows App Runtime
# (lib/basket/winui.rb), tested through WinUI's controls: each test
# makes the screen, clicks its buttons as UI Automation does, which raises
# their Click events, and reads what the list and the rows then hold. No
# window is shown. It runs as any Ruby test does, on a Windows that has the
# Windows App Runtime:
#
#   ruby test/winui_test.rb
#
# and each test says why it does not run where it cannot.

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../lib/basket/list"
require_relative "../lib/basket/winui"

# Why these tests cannot run on this computer, or nil when they can: the
# screen is WinUI's, which needs Windows and its Windows App Runtime.
WINUI_UNAVAILABLE = if !Gem.win_platform?
  "Basket's WinUI screen draws with the Windows App Runtime, which only Windows has"
elsif !Basket::WinUI.available?
  "this Windows has no Windows App Runtime 2.7 or later, which Basket's WinUI screen draws with"
end

# The tests of Basket::WinUI::Screen, with WinUI's controls.
class WinUIScreenTest < Minitest::Test
  # A FrameworkElementAutomationPeer's static methods: CreatePeerForElement 7.
  PEER_STATICS = "081f6fbe-6500-528a-a506-f5a4d41ddf6c"
  # An AutomationPeer: GetPattern 8.
  AUTOMATION_PEER = "e51d3e4e-34f0-568c-999f-6277e2afe6d7"
  # What a button answers to be invoked: Invoke 6.
  INVOKE_PROVIDER = "02481105-3378-544d-b4e1-a1b368afbc02"

  # Runs the tests on the thread that WinUI has, which is the one that
  # calls the block of WinRT.start, and ends the application when they
  # are done. Without the Windows App Runtime each test skips as usual.
  def self.run(*)
    return super if WINUI_UNAVAILABLE

    result = nil
    Basket::WinRT.start do
      result = super(*)
    ensure
      Basket::WinRT.quit
    end
    result
  end

  # A list in a folder made for the test.
  def setup
    skip WINUI_UNAVAILABLE if WINUI_UNAVAILABLE

    @dir = Dir.mktmpdir
    @list = Basket::List.new(File.join(@dir, "basket.json"))
  end

  # Deletes the test's folder.
  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  # The screen of the test's list, after it takes +items+ as it would
  # have had them from its file.
  def screen(*items)
    items.each { |item| @list.add(item) }
    Basket::WinUI::Screen.new(@list)
  end

  # Clicks +button+ as UI Automation does, which raises its Click event.
  def click(button)
    peers = Basket::WinRT.factory("Microsoft.UI.Xaml.Automation.Peers.FrameworkElementAutomationPeer", PEER_STATICS)
    peer = peers.out_object(7, [Basket::WinRT::POINTER], button.qi(Basket::WinUI::IID_UIELEMENT).ptr)
    peer.qi(AUTOMATION_PEER).out_object(8, [Basket::WinRT::INT], 0).qi(INVOKE_PROVIDER).hr(6)
  end

  # The list shows a row for each of its items.
  def test_it_shows_a_row_for_each_item
    shown = screen("Milk", "Eggs")

    assert_equal 2, shown.rows
    assert_equal %w[Milk Eggs], shown.items
  end

  # A click on Add takes what the text box holds into the list and a
  # row, and empties the text box.
  def test_adding_puts_what_the_text_box_holds_in_the_list_and_empties_it
    shown = screen
    shown.text = "Milk"
    click(shown.add_button)

    assert_equal ["Milk"], @list.items
    assert_equal ["Milk"], shown.items
    assert_equal "", shown.text
  end

  # A text box with only spaces adds nothing.
  def test_adding_nothing_adds_nothing
    shown = screen
    shown.text = "  "
    click(shown.add_button)

    assert_empty @list.items
    assert_equal 0, shown.rows
  end

  # Return, pressed in the text box, adds as the Add button does.
  def test_return_in_the_text_box_adds
    shown = screen
    shown.text = "Eggs"
    shown.press(:field, Basket::WinUI::RETURN_KEY)

    assert_equal ["Eggs"], @list.items
    assert_equal ["Eggs"], shown.items
  end

  # Remove takes the selected item out of the list and its row away,
  # and selects the item that takes its place.
  def test_removing_takes_the_selected_item_and_its_row_away
    shown = screen("Milk", "Eggs", "Bread")
    shown.select(1)
    click(shown.remove_button)

    assert_equal %w[Milk Bread], @list.items
    assert_equal %w[Milk Bread], shown.items
    assert_equal 1, shown.selected
  end

  # Remove with no row selected removes nothing.
  def test_removing_with_no_row_selected_removes_nothing
    shown = screen("Milk")
    click(shown.remove_button)

    assert_equal ["Milk"], @list.items
    assert_equal 1, shown.rows
  end

  # Delete, pressed in the list, removes the selected row as Remove does;
  # in the text box it removes nothing.
  def test_delete_in_the_list_removes_the_selected_row
    shown = screen("Milk", "Eggs")
    shown.select(0)
    shown.press(:field, Basket::WinUI::DELETE_KEY)

    assert_equal 2, shown.rows

    shown.press(:list, Basket::WinUI::DELETE_KEY)

    assert_equal ["Eggs"], @list.items
  end

  # A window's HWND, made as Basket makes its window.
  def window_handle
    Basket::WinUI.handle(Basket::WinUI.show(Basket::WinUI::Screen.new(@list)))
  end

  # A function of user32.dll or dwmapi.dll, which each take a window.
  def native(file, name, args, ret)
    Basket::WinRT::Win.function(file, name, args, ret)
  end

  # Whether the title bar of the window at +handle+ is dark, as DWM has it.
  def title_dark?(handle)
    mode = Basket::WinRT::Win.buffer(4)
    native("dwmapi.dll", "DwmGetWindowAttribute", [Basket::WinRT::POINTER, Basket::WinRT::INT, Basket::WinRT::POINTER, Basket::WinRT::INT], Basket::WinRT::INT)
      .call(handle, Basket::WinUI::USE_IMMERSIVE_DARK_MODE, mode, 4)
    mode[0, 4].unpack1("l") != 0
  end

  # Makes the title bar of the window at +handle+ dark or light, as Windows
  # leaves it until Basket asks.
  def title_dark=(dark)
    mode = Basket::WinRT::Win.buffer(4)
    mode[0, 4] = [dark ? 1 : 0].pack("l")
    native("dwmapi.dll", "DwmSetWindowAttribute", [Basket::WinRT::POINTER, Basket::WinRT::INT, Basket::WinRT::POINTER, Basket::WinRT::INT], Basket::WinRT::INT)
      .call(@handle, Basket::WinUI::USE_IMMERSIVE_DARK_MODE, mode, 4)
  end

  # Sends the window at +handle+ the message +message+, as Windows does:
  # SendMessageW, which returns once the window's procedure has run.
  def send_message(handle, message, wparam, lparam)
    native("user32.dll", "SendMessageW", [Basket::WinRT::POINTER, Basket::WinRT::UINT, Basket::WinRT::INT64, Basket::WinRT::INT64], Basket::WinRT::INT64)
      .call(handle, message, wparam, lparam)
  end

  # The window's left, top, right, and bottom edges, in pixels.
  def window_rect(handle)
    rect = Basket::WinRT::Win.buffer(16)
    native("user32.dll", "GetWindowRect", [Basket::WinRT::POINTER, Basket::WinRT::POINTER], Basket::WinRT::INT).call(handle, rect)
    rect[0, 16].unpack("l4")
  end

  # When Windows says the app mode changed (WM_SETTINGCHANGE with
  # "ImmersiveColorSet"), the title bar takes the mode's colors.
  def test_title_bar_follows_a_change_of_app_mode
    @handle = window_handle
    self.title_dark = !Basket::WinUI.dark?
    setting = Basket::WinRT::Win.wide("ImmersiveColorSet")
    send_message(@handle, Basket::WinUI::WM_SETTINGCHANGE, 0, setting.to_i)

    assert_equal Basket::WinUI.dark?, title_dark?(@handle)
  end

  # Another setting's change leaves the title bar as it is.
  def test_title_bar_ignores_other_settings
    @handle = window_handle
    self.title_dark = !Basket::WinUI.dark?
    setting = Basket::WinRT::Win.wide("intl")
    send_message(@handle, Basket::WinUI::WM_SETTINGCHANGE, 0, setting.to_i)

    assert_equal !Basket::WinUI.dark?, title_dark?(@handle)
  end

  # When Windows moves the window to a monitor of another scale
  # (WM_DPICHANGED), the window takes the rectangle Windows suggests for
  # the new scale, as Microsoft's page on the message says an app does.
  def test_window_takes_the_rectangle_windows_suggests_for_a_new_scale
    handle = window_handle
    suggested = Basket::WinRT::Win.buffer(16)
    suggested[0, 16] = [100, 120, 100 + 960, 120 + 1280].pack("l4")
    send_message(handle, Basket::WinUI::WM_DPICHANGED, (192 << 16) | 192, suggested.to_i)

    assert_equal [100, 120, 1060, 1400], window_rect(handle)
  end
end

# What chooses the screen, which every Windows and every other system can ask.
class WinUIChoiceTest < Minitest::Test
  # A person can make Basket draw Win32's screen where Windows has the
  # Windows App Runtime, with BASKET_SCREEN, whatever Windows has.
  def test_win32_screen_can_be_asked_for
    was = ENV.fetch("BASKET_SCREEN", nil)
    ENV["BASKET_SCREEN"] = "win32"

    refute_predicate Basket::WinUI, :available?
  ensure
    ENV["BASKET_SCREEN"] = was
  end
end

# The window's size, which every system can compute.
class WinUIWindowSizeTest < Minitest::Test
  # Microsoft's effective pixels are 1 to 1 at 96 DPI, which Windows calls 100 percent.
  def test_size_at_100_percent_is_the_effective_size
    assert_equal [480, 640], Basket::WinUI.window_pixels(96)
  end

  # Windows scales a window by the monitor's DPI over 96.
  def test_size_grows_with_the_monitor_scale
    assert_equal [720, 960], Basket::WinUI.window_pixels(144)
    assert_equal [1200, 1600], Basket::WinUI.window_pixels(240)
  end
end
