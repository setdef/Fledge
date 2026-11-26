# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "win32"

module Basket
  # Basket's screen on Windows, drawn by Win32's common controls: a text
  # field and an Add button above a list, and a Remove button below it.
  # Add is the window's default button, so Return in the field adds, and
  # Delete in the list removes the selected row, as in Microsoft's
  # lists. Each control is Windows', made and sent its messages as
  # Microsoft documents them, through Basket::Win32, which is Fiddle, a
  # library Ruby bundles, and nothing else.
  module Windows
    # The manifest that asks for Common Controls 6, whose controls have
    # Windows 11's rounded corners and colors.
    MANIFEST = File.join(__dir__, "common-controls.manifest")
    # The id the window hears the Add button by, which is its default.
    ADD = 101
    # The id the window hears the Remove button by.
    REMOVE = 102
    # VK_DELETE
    DELETE_KEY = 0x2E

    # The window's controls, and what adding and removing an item does to them.
    class Screen
      # The window the controls are in.
      attr_reader :window

      # The text field a person types an item in.
      attr_reader :field

      # The Add and Remove buttons.
      attr_reader :add_button, :remove_button

      # The list of rows.
      attr_reader :table

      # The screen of +list+, a List.
      def initialize(list)
        Win32.prepare(MANIFEST)
        @list = list
        @window = Win32::Window.open("Basket", width: 520, height: 420, default_button: ADD)
        @field = Win32::Edit.new(@window, cue: "Add an item")
        @add_button = Win32::Button.new(@window, "Add", id: ADD, default: true)
        @table = Win32::ListView.new(@window)
        @remove_button = Win32::Button.new(@window, "Remove", id: REMOVE)
        list.items.each { |item| @table.add(item) }
        @window.on_command(ADD) { add }
        @window.on_command(REMOVE) { remove }
        @window.on_key_down(@table) { |key| remove if key == DELETE_KEY }
        @window.on_size { |width, height| place(width, height) }
      end

      # Shows the window, with the keyboard in the field.
      def show
        @window.show
        @field.focus
      end

      # Adds what the field holds, and empties the field.
      def add
        item = @list.add(@field.text) or return

        @table.add(item)
        @field.text = ""
        @field.focus
        puts "Basket added #{item}"
      end

      # Removes the selected item, and selects the one that takes its
      # place, so the keyboard can go on removing.
      def remove
        index = @table.selected or return

        item = @list.remove(index)
        @table.remove(index)
        @table.select([index, @table.count - 1].min) unless @table.count.zero?
        puts "Basket removed #{item}"
      end

      # How many rows the list shows.
      def rows
        @table.count
      end

      # Selects the row at +index+, as a click on it does.
      def select(index)
        @table.select(index)
      end

      # Puts the controls in the window, within the margins Microsoft's
      # guidelines give a window's content: 16 pixels, with 8 between
      # controls, at 96 dots per inch. The field and the buttons are 23
      # pixels high, which Microsoft's layout guidelines give a one-line
      # text box and a command button ("Recommended sizing and spacing"):
      # a taller field draws its text at the top, where only a field of
      # one line's height has it centered.
      private def place(width, height)
        margin = @window.scale(16)
        gap = @window.scale(8)
        row = @window.scale(23)
        button = @window.scale(88)
        @field.move(margin, margin, width - (2 * margin) - button - gap, row)
        @add_button.move(width - margin - button, margin, button, row)
        top = margin + row + gap
        bottom = height - margin - row
        @table.move(margin, top, width - (2 * margin), bottom - gap - top)
        @table.fit_column
        @remove_button.move(width - margin - button, bottom, button, row)
      end
    end

    # Runs Basket: shows its screen and handles the window's messages
    # until the window is closed.
    def self.run(list)
      screen = Screen.new(list)
      screen.show
      rows = screen.rows
      puts "Basket shows #{rows} #{(rows == 1) ? 'item' : 'items'}"
      Win32.run(screen.window)
    end
  end
end
