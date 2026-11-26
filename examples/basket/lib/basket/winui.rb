# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "winrt"

module Basket
  # Basket's screen on Windows 11 with the Windows App Runtime, drawn by
  # WinUI 3: a text box and an Add button above a list, and a Remove
  # button below it, in Fluent's styles. Return in the text box adds, and
  # Delete in the list removes the selected row, as in Microsoft's
  # lists. Each control is WinUI's, made from the markup a WinUI app
  # writes in XAML and sent its calls as Microsoft documents them,
  # through Basket::WinRT, which is Fiddle, a library Ruby bundles, and
  # nothing else. Where Windows has no Windows App Runtime, Basket
  # draws Basket::Windows instead.
  module WinUI
    # The interfaces the screen calls, by IID, with the methods it calls
    # at their places in the interface, from Microsoft.UI.Xaml.winmd.
    # A Window: put_Content 9, put_Title 15, Activate 26.
    IID_WINDOW = "61f0ec79-5d52-56b5-86fb-40fa4af288b0"
    # What a Window answers to give the HWND that holds it, an IUnknown
    # interface: get_WindowHandle 3.
    IID_WINDOW_NATIVE = "eecdbf0e-bae9-4cb6-a68e-9598e1cb57bb"
    # XamlReader's static methods: Load 6.
    IID_XAML_READER_STATICS = "82a4cd9e-435e-5aeb-8c4f-300cece45cae"
    # A FrameworkElement: FindName 77.
    IID_FRAMEWORK_ELEMENT = "fe08f13d-dc6a-5495-ad44-c2d8d21863b0"
    # A UIElement: add_KeyDown 132, Focus 226.
    IID_UIELEMENT = "c3c01020-320c-5cf6-9d24-d396bbfa4d8b"
    # A TextBox: get_Text 6, put_Text 7.
    IID_TEXTBOX = "873af7c2-ab89-5d76-8dbe-3d6325669df5"
    # A ButtonBase: add_Click 14.
    IID_BUTTON_BASE = "65714269-2473-5327-a652-0ea6bce7f403"
    # An ItemsControl: get_Items 8.
    IID_ITEMS_CONTROL = "bf1ccb54-83e2-5b98-acbc-736f876c3d35"
    # A Selector: get_SelectedIndex 6, put_SelectedIndex 7.
    IID_SELECTOR = "8f7e2159-e61d-576f-8476-f83fde3d689e"
    # The items of a list, an IVector of Object: GetAt 6, get_Size 7,
    # RemoveAt 12, Append 13.
    IID_VECTOR = "b32bdca4-5e52-5b27-bc5d-d66a1a268c2a"
    # The delegate of Click, a RoutedEventHandler.
    IID_ROUTED_HANDLER = "dae23d85-69ca-5bdf-805b-6161a3a215cc"
    # The delegate of KeyDown, a KeyEventHandler.
    IID_KEY_HANDLER = "db68e7cc-9a2b-527d-9989-25284daccc03"
    # What a KeyDown handler is told: get_Key 6.
    IID_KEY_ARGS = "ee357007-a2d6-5c75-9431-05fd66ec7915"

    # VirtualKey.Enter
    RETURN_KEY = 13
    # VirtualKey.Delete
    DELETE_KEY = 0x2E
    # FocusState.Programmatic
    PROGRAMMATIC = 3
    # What a SelectedIndex is when no row is selected.
    NONE = -1

    # The window's size in effective pixels, which Windows scales for
    # each monitor: Microsoft's "Screen sizes and breakpoints for
    # responsive design" gives 480 by 854 for a window of the small
    # class, which a column of rows is, and says a PC's windows are 1024
    # by 640 or more. A list takes 480 for its width and 640 for its
    # height, which fits a 1366 by 768 screen at 100 percent.
    WINDOW_SIZE = [480, 640].freeze
    # What a monitor at 100 percent scale has for DPI.
    BASE_DPI = 96
    # SWP_NOZORDER, SWP_NOMOVE, and SWP_NOACTIVATE, for SetWindowPos.
    KEEP_PLACE = 0x0004 | 0x0002 | 0x0010
    # HKEY_CURRENT_USER, which a 64-bit HKEY holds sign-extended, as a signed number.
    HKEY_CURRENT_USER = -0x7fffffff
    # RRF_RT_REG_DWORD
    REG_DWORD = 0x10
    # Where Windows keeps the person's choice of light or dark.
    PERSONALIZE = 'Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize'
    # DWMWA_USE_IMMERSIVE_DARK_MODE
    USE_IMMERSIVE_DARK_MODE = 20

    # The screen's controls, with the margins and gaps Microsoft's
    # guidelines give: 16 pixels around the content and 8 between
    # controls, and the list takes the height the window has.
    MARKUP = <<~XAML
      <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Background="{ThemeResource ApplicationPageBackgroundThemeBrush}"
            Padding="16" RowSpacing="8">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid ColumnSpacing="8">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="Field" PlaceholderText="Add an item"/>
          <Button x:Name="AddButton" Grid.Column="1" Content="Add" Style="{StaticResource AccentButtonStyle}"/>
        </Grid>
        <ListView x:Name="Rows" Grid.Row="1"/>
        <Button x:Name="RemoveButton" Grid.Row="2" Content="Remove" HorizontalAlignment="Right"/>
      </Grid>
    XAML

    # The screen's controls, and what adding and removing an item does to them.
    class Screen
      # The top control of the screen, which a window holds as its content.
      attr_reader :content

      # The Add and Remove buttons.
      attr_reader :add_button, :remove_button

      # The screen of +list+, a List.
      def initialize(list)
        @list = list
        reader = WinRT.factory("Microsoft.UI.Xaml.Markup.XamlReader", IID_XAML_READER_STATICS)
        @content = reader.out_object(6, [WinRT::POINTER], WinRT::Win.hstring(MARKUP), what: "XamlReader.Load")
        field = named("Field")
        @field = field.qi(IID_TEXTBOX)
        @focusable = field.qi(IID_UIELEMENT)
        @add_button = named("AddButton").qi(IID_BUTTON_BASE)
        @remove_button = named("RemoveButton").qi(IID_BUTTON_BASE)
        rows = named("Rows")
        @table = rows.qi(IID_SELECTOR)
        @items = rows.qi(IID_ITEMS_CONTROL).out_object(8, what: "get_Items").qi(IID_VECTOR)
        list.items.each { |item| @items.hr(13, [WinRT::POINTER], WinRT.box(item), what: "Append") }
        WinRT.subscribe(@add_button, 14, IID_ROUTED_HANDLER) { |_sender, _args| add }
        WinRT.subscribe(@remove_button, 14, IID_ROUTED_HANDLER) { |_sender, _args| remove }
        WinRT.subscribe(@focusable, 132, IID_KEY_HANDLER) { |_sender, args| press(:field, key(args)) }
        WinRT.subscribe(rows.qi(IID_UIELEMENT), 132, IID_KEY_HANDLER) { |_sender, args| press(:list, key(args)) }
      end

      # Gives the keyboard to the text box.
      def focus
        @focusable.out(226, [WinRT::INT], PROGRAMMATIC, what: "Focus")
      end

      # Adds what the text box holds, and empties it.
      def add
        item = @list.add(text) or return

        @items.hr(13, [WinRT::POINTER], WinRT.box(item), what: "Append")
        self.text = ""
        focus
        puts "Basket added #{item}"
      end

      # Removes the selected item, and selects the one that takes its
      # place, so the keyboard can go on removing.
      def remove
        index = selected or return

        item = @list.remove(index)
        @items.hr(12, [WinRT::UINT], index, what: "RemoveAt")
        @table.hr(7, [WinRT::INT], [index, rows - 1].min, what: "put_SelectedIndex") unless rows.zero?
        puts "Basket removed #{item}"
      end

      # The index of the selected row, or nil when none is.
      def selected
        index = @table.out_int(6, what: "get_SelectedIndex")
        index unless index == NONE
      end

      # How many rows the list shows.
      def rows
        @items.out(7, what: "get_Size") & 0xffffffff
      end

      # The text of each row.
      def items
        Array.new(rows) do |index|
          row = @items.out_object(6, [WinRT::UINT], index, what: "GetAt")
          row.qi(WinRT::IID_PROPERTY_VALUE).out_string(19, what: "GetString")
        end
      end

      # Selects the row at +index+, as a click on it does.
      def select(index)
        @table.hr(7, [WinRT::INT], index, what: "put_SelectedIndex")
      end

      # What the text box holds.
      def text
        @field.out_string(6, what: "get_Text")
      end

      # What the key +code+ does where the keyboard is, in the text box
      # (+control+ is :field) or the list (:list): Return adds in the text
      # box, and Delete removes in the list.
      def press(control, code)
        add if control == :field && code == RETURN_KEY
        remove if control == :list && code == DELETE_KEY
      end

      # Puts +value+ in the text box.
      def text=(value)
        @field.hr(7, [WinRT::POINTER], WinRT::Win.hstring(value), what: "put_Text")
      end

      # The virtual key that a KeyDown handler is told of in +args+.
      private def key(args)
        WinRT::Interface.new(args.to_i).qi(IID_KEY_ARGS).out(6, what: "get_Key") & 0xffffffff
      end

      # The control that the markup gives the x:Name +name+.
      private def named(name)
        @content.qi(IID_FRAMEWORK_ELEMENT).out_object(77, [WinRT::POINTER], WinRT::Win.hstring(name), what: "FindName #{name}")
      end
    end

    # Whether this Windows has what Basket::WinUI needs: the Windows App
    # Runtime, which Windows 11 and Windows 10 get from the Microsoft
    # Store, or with Microsoft's installer. A person can make Basket draw
    # Win32's screen instead by setting BASKET_SCREEN to win32.
    def self.available?
      ENV["BASKET_SCREEN"] != "win32" && WinRT.available?
    end

    # The window's width and height in pixels on a monitor of +dpi+.
    def self.window_pixels(dpi)
      WINDOW_SIZE.map { |epx| (epx * dpi / BASE_DPI.to_f).round }
    end

    # Whether Windows asks apps for their dark colors: the person's
    # "Choose your default app mode", which WinUI reads for the colors of
    # the controls, and which Windows keeps as AppsUseLightTheme, a DWORD,
    # in the person's registry.
    def self.dark?
      data = WinRT::Win.buffer(4)
      size = WinRT::Win.buffer(4)
      size[0, 4] = [4].pack("L")
      status = WinRT::Win.function("advapi32.dll", "RegGetValueW", [WinRT::INT64, WinRT::POINTER, WinRT::POINTER, WinRT::UINT, WinRT::POINTER, WinRT::POINTER, WinRT::POINTER], WinRT::INT)
        .call(HKEY_CURRENT_USER, WinRT::Win.wide(PERSONALIZE), WinRT::Win.wide("AppsUseLightTheme"), REG_DWORD, nil, data, size)
      status.zero? && data[0, 4].unpack1("L").zero?
    end

    # Fits +window+ to the monitor it is on: WINDOW_SIZE at the monitor's
    # scale, leaving where it is alone, and a title bar in the colors the
    # controls take, since Windows draws the title bar of a window like this
    # one in its light colors until the app asks for dark.
    def self.fit(window)
      handle = window.qi(IID_WINDOW_NATIVE).out(3, what: "get_WindowHandle")
      dpi = WinRT::Win.function("user32.dll", "GetDpiForWindow", [WinRT::POINTER], WinRT::INT).call(handle)
      width, height = window_pixels(dpi.zero? ? BASE_DPI : dpi)
      WinRT::Win.function("user32.dll", "SetWindowPos", [WinRT::POINTER, WinRT::POINTER, WinRT::INT, WinRT::INT, WinRT::INT, WinRT::INT, WinRT::UINT], WinRT::INT)
        .call(handle, 0, 0, 0, width, height, KEEP_PLACE)
      mode = WinRT::Win.buffer(4)
      mode[0, 4] = [dark? ? 1 : 0].pack("l")
      WinRT::Win.function("dwmapi.dll", "DwmSetWindowAttribute", [WinRT::POINTER, WinRT::INT, WinRT::POINTER, WinRT::INT], WinRT::INT)
        .call(handle, USE_IMMERSIVE_DARK_MODE, mode, 4)
    end

    # Runs Basket: gives the main thread to WinUI, which then calls for the
    # window, where Screen goes.
    def self.run(list)
      WinRT.start do
        screen = Screen.new(list)
        window = WinRT.activate("Microsoft.UI.Xaml.Window").qi(IID_WINDOW)
        window.hr(9, [WinRT::POINTER], screen.content.ptr, what: "put_Content")
        window.hr(15, [WinRT::POINTER], WinRT::Win.hstring("Basket"), what: "put_Title")
        window.hr(26, what: "Activate")
        fit(window)
        screen.focus
        WinRT::Implementation::KEEP << window << screen
        rows = screen.rows
        puts "Basket shows #{rows} #{(rows == 1) ? 'item' : 'items'}"
      end
    end
  end
end
