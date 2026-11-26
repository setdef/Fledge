# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "objc"

module Basket
  # Basket's screen on a Mac, drawn by AppKit: a window with a text field
  # and an Add button above a table, and the main menu Apple's Human
  # Interface Guidelines list for an app. Return presses Add, which is the
  # window's default button. A row goes by Edit > Delete (Command-Delete),
  # by its context menu, or by the Delete key, which the guidelines say
  # are one command. Each object is an AppKit object, made and sent its
  # messages as Apple documents them, through Basket::ObjC, which is
  # Fiddle, a library Ruby bundles, and nothing else.
  module MacOS
    # AppKit, loaded into the process, which an Objective-C program's
    # code would have linked.
    ObjC.load_framework("AppKit") || raise(LoadError, "Basket::MacOS needs AppKit, which this system does not have")

    # AppKit's constants this screen passes, from AppKit's headers.
    # NSUserInterfaceLayoutOrientationHorizontal
    HORIZONTAL = 0
    # NSUserInterfaceLayoutOrientationVertical
    VERTICAL = 1
    # NSEventModifierFlagCommand
    COMMAND = 1 << 20
    # NSEventModifierFlagOption
    OPTION = 1 << 19
    # NSTableViewAnimationSlideUp
    SLIDE_UP = 0x10
    # NSApplicationActivationPolicyRegular
    REGULAR = 0
    # NSBackspaceCharacter, the Delete key's key equivalent
    BACKSPACE = "\b"
    # The distance of a window's content from its edges, which Apple's
    # guidelines give a window.
    MARGIN = 20.0
    # The distance between a window's controls.
    SPACING = 8.0

    # What the Add button, the Return key, and the Delete items do.
    class Actions < ObjC::NSObject
      objc_protocols "NSMenuItemValidation"

      # The Screen whose controls these are.
      attr_accessor :screen

      # No protocol lists +add:+ or +remove:+, so their type encodings
      # are given: no result, then the receiver, the selector, and the
      # sender.
      objc_method("add:", "v24@0:8@16") { |_sender| screen.add }
      objc_method("remove:", "v24@0:8@16") { |_sender| screen.remove }

      # Delete is on while there is a row to delete.
      objc_method("validateMenuItem:") do |item|
        (item.action.to_i == ObjC.selector("remove:")) ? screen.row_to_remove >= 0 : true
      end
    end

    # The table's rows, which AppKit asks for as it draws them, each in a
    # table cell view, so that it has the inset of AppKit's lists.
    class Rows < ObjC::NSObject
      objc_protocols "NSTableViewDataSource", "NSTableViewDelegate"

      # The List the rows show.
      attr_accessor :list

      objc_method("numberOfRowsInTableView:") { |_table| list.items.size }

      objc_method("tableView:viewForTableColumn:row:") do |table, _column, row|
        cell = table.makeViewWithIdentifier("item", owner: nil) || new_cell
        cell.textField.stringValue = list.items.fetch(row)
        cell
      end

      # A cell view of a label, which the table reuses for each row.
      private def new_cell
        label = ObjC::NSTextField.labelWithString("")
        label.translatesAutoresizingMaskIntoConstraints = false
        cell = ObjC::NSTableCellView.new
        cell.identifier = "item"
        cell.textField = label
        cell.addSubview(label)
        ObjC::NSLayoutConstraint.activateConstraints([
          label.leadingAnchor.constraintEqualToAnchor(cell.leadingAnchor, constant: 2.0),
          label.trailingAnchor.constraintEqualToAnchor(cell.trailingAnchor, constant: -2.0),
          label.centerYAnchor.constraintEqualToAnchor(cell.centerYAnchor),
        ])
        cell
      end
    end

    # A table whose Delete key deletes the selected row: NSTableView's
    # keyDown: hands a key to interpretKeyEvents:, which sends the
    # responder chain deleteBackward: or deleteForward:.
    class Table < ObjC::NSTableView
      # The Screen whose rows these are.
      attr_accessor :screen

      objc_method("deleteBackward:", "v24@0:8@16") { |_sender| screen.remove }
      objc_method("deleteForward:", "v24@0:8@16") { |_sender| screen.remove }
    end

    # The screen's window, and what adding and removing do to it.
    class Screen
      # The window.
      attr_reader :window

      # The text field a person types an item in.
      attr_reader :field

      # The Add button, the window's default button.
      attr_reader :button

      # The table of items.
      attr_reader :table

      # The Actions the buttons and the menu items send.
      attr_reader :actions

      # The screen of +list+, a List.
      def initialize(list)
        @list = list
        @actions = Actions.new.tap { |actions| actions.screen = self }
        @rows = Rows.new.tap { |rows| rows.list = list }
        controller = ObjC::NSViewController.new
        controller.view = column
        @window = ObjC::NSWindow.windowWithContentViewController(controller)
        @window.title = "Basket"
        @window.setContentSize([480.0, 360.0])
        @window.center
        @controller = controller
      end

      # Adds what the field holds, and empties the field.
      def add
        item = @list.add(@field.stringValue.to_s) or return

        @field.stringValue = ""
        @table.reloadData
        puts "Basket added #{item}"
      end

      # Removes the row a context menu opened on, or else the selected row.
      def remove
        row = row_to_remove
        return if row.negative?

        item = @list.remove(row)
        @table.removeRowsAtIndexes(ObjC::NSIndexSet.indexSetWithIndex(row), withAnimation: SLIDE_UP)
        puts "Basket removed #{item}"
      end

      # The row a context menu opened on, else the selected row, else -1.
      def row_to_remove
        row = @table.clickedRow
        row.negative? ? @table.selectedRow : row
      end

      # How many rows the table shows, as AppKit asks Rows.
      def rows
        @table.numberOfRows
      end

      private def column
        stack = ObjC::NSStackView.stackViewWithViews([entry, scroll])
        stack.orientation = VERTICAL
        stack.spacing = SPACING
        stack.edgeInsets = [MARGIN, MARGIN, MARGIN, MARGIN]
        stack.widthAnchor.constraintGreaterThanOrEqualToConstant(360.0).active = true
        stack
      end

      private def entry
        @field = ObjC::NSTextField.new
        @field.placeholderString = "Add an item"
        @button = ObjC::NSButton.buttonWithTitle("Add", target: @actions, action: "add:")
        @button.keyEquivalent = "\r"
        row = ObjC::NSStackView.stackViewWithViews([@field, @button])
        row.orientation = HORIZONTAL
        row.spacing = SPACING
        row
      end

      private def scroll
        scroll = ObjC::NSScrollView.new
        scroll.hasVerticalScroller = true
        scroll.documentView = table_view
        scroll.heightAnchor.constraintGreaterThanOrEqualToConstant(160.0).active = true
        scroll
      end

      private def table_view
        @table = Table.new
        @table.screen = self
        @table.addTableColumn(ObjC::NSTableColumn.alloc.initWithIdentifier("item"))
        @table.headerView = nil
        @table.dataSource = @rows
        @table.delegate = @rows
        @table.usesAutomaticRowHeights = true
        @table.menu = Menus.menu("Row", [["Delete", "remove:", "", 0, @actions]])
        @table
      end
    end

    # The main menu, by the order and contents Apple's guidelines give:
    # the app's menu, File, Edit, and Window. Edit is there for the text
    # field, which gets Cut, Copy, and Paste from it, and for Delete.
    module Menus
      # The menu +title+ of +items+, each a title, an action, a key
      # equivalent, the modifier keys of that (Command alone when it
      # gives none), and a target; a title of nil is a separator. An item
      # with no target goes to the first responder.
      def self.menu(title, items)
        menu = ObjC::NSMenu.alloc.initWithTitle(title)
        items.each do |name, action, key, modifiers, target|
          item = if name
            ObjC::NSMenuItem.alloc.initWithTitle(name, action:, keyEquivalent: key).tap do |made|
              made.keyEquivalentModifierMask = modifiers unless modifiers.nil?
              made.target = target if target
            end
          else
            ObjC::NSMenuItem.separatorItem
          end
          menu.addItem(item)
        end
        menu
      end

      # The menu bar for +actions+, and its Window menu, which AppKit
      # keeps the window titles in.
      def self.bar(actions)
        bar = ObjC::NSMenu.alloc.initWithTitle("")
        menus = {
          "Basket" => [
            ["About Basket", "orderFrontStandardAboutPanel:", ""],
            [nil],
            ["Hide Basket", "hide:", "h"],
            ["Hide Others", "hideOtherApplications:", "h", COMMAND | OPTION],
            ["Show All", "unhideAllApplications:", ""],
            [nil],
            ["Quit Basket", "terminate:", "q"],
          ],
          "File" => [["Close", "performClose:", "w"]],
          "Edit" => [
            ["Undo", "undo:", "z"],
            ["Redo", "redo:", "Z"],
            [nil],
            ["Cut", "cut:", "x"],
            ["Copy", "copy:", "c"],
            ["Paste", "paste:", "v"],
            ["Delete", "remove:", BACKSPACE, COMMAND, actions],
            ["Select All", "selectAll:", "a"],
          ],
          "Window" => [
            ["Minimize", "performMiniaturize:", "m"],
            ["Zoom", "performZoom:", ""],
          ],
        }
        submenus = menus.map do |title, items|
          holder = ObjC::NSMenuItem.alloc.initWithTitle(title, action: nil, keyEquivalent: "")
          holder.submenu = menu(title, items)
          bar.addItem(holder)
          holder.submenu
        end
        [bar, submenus.last]
      end
    end

    # The application's delegate, which puts Basket's screen and menu
    # where AppKit shows them, and quits with the last window.
    class Delegate < ObjC::NSObject
      objc_protocols "NSApplicationDelegate"

      class << self
        # The List the screen shows.
        attr_accessor :list
      end

      objc_method("applicationDidFinishLaunching:") do |_notification|
        app = ObjC::NSApplication.sharedApplication
        @screen = Screen.new(Delegate.list)
        app.mainMenu, app.windowsMenu = Menus.bar(@screen.actions)
        @screen.window.makeKeyAndOrderFront(nil)
        app.activate
        rows = @screen.rows
        puts "Basket shows #{rows} #{(rows == 1) ? 'item' : 'items'}"
      end

      objc_method("applicationShouldTerminateAfterLastWindowClosed:") { |_application| true }
    end

    # Runs Basket: hands the main thread to AppKit, which then tells the
    # delegate the app has launched, where Screen goes. What Basket prints
    # reaches a log line by line, as it would in a terminal, since the app
    # ends when AppKit exits, without Ruby flushing a file or a pipe.
    def self.run(list)
      $stdout.sync = true
      Delegate.list = list
      app = ObjC::NSApplication.sharedApplication
      app.setActivationPolicy(REGULAR)
      app.delegate = Delegate.new
      app.run
    end
  end
end
