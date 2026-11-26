# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Drives Basket's Mac screen as a person does, and quits. deliver-basket-mac.sh
# puts it beside Basket's main.rb in a copy of the built app and names it
# the entry in fledge.cfg, so the app's launcher runs it as the program,
# with the app's Ruby and gems:
#
#   Basket.app/Contents/MacOS/Basket
#
# The script prepares one call a second after AppKit starts, then loads
# the app's main.rb, which opens the window and hands the main thread to
# AppKit, so the call runs inside the app's run loop. It types Milk into
# the text field, presses Add, selects the row, and chooses Edit > Delete,
# as the pointer does; Basket prints what it did.

$stdout.sync = true
require_relative "lib/basket/objc"
ObjC = Basket::ObjC
ObjC.load_framework("AppKit") || abort("this computer has no AppKit")

# The one call: what a person does with Basket, and then quitting.
class BasketDriver < ObjC::NSObject
  objc_method("drive:", "v24@0:8@16") do |_sender|
    app = ObjC::NSApplication.sharedApplication
    screen = app.delegate.instance_variable_get(:@screen) || abort("Basket made no screen")
    screen.field.stringValue = "Milk"
    screen.button.performClick(nil)
    abort "adding Milk left #{screen.rows} rows" unless screen.rows == 1
    screen.table.selectRowIndexes(ObjC::NSIndexSet.indexSetWithIndex(0), byExtendingSelection: false)
    edit = app.mainMenu.itemArray.to_a.find { |item| item.title.to_s == "Edit" }
    delete = edit.submenu.itemArray.to_a.find { |item| item.title.to_s == "Delete" }
    abort "Edit > Delete is off with a row selected" unless screen.actions.validateMenuItem(delete)
    delete.menu.performActionForItemAtIndex(delete.menu.indexOfItem(delete))
    abort "deleting Milk left #{screen.rows} rows" unless screen.rows.zero?
    app.terminate(nil)
  end
end

BasketDriver.new.performSelector(:"drive:", withObject: nil, afterDelay: 1.0)
load File.join(__dir__, "main.rb")
