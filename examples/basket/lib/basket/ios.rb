# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0

require "fledge/objc"

module Basket
  # Basket's screen on iOS and iPadOS, drawn by UIKit: a table under a
  # navigation bar with a large title, and a text field with an Add
  # button above it. Swiping a row left deletes it, as in Apple's own
  # lists. Each object is UIKit's own, made and sent its messages as
  # Apple documents them, through Fledge::ObjC.
  module IOS
    # The runtime's bridge to the Objective-C runtime.
    ObjC = Fledge::ObjC

    # UIKit's constants this screen passes, from UIKit's headers.
    # UITextBorderStyleRoundedRect
    ROUNDED_RECT = 3
    # UIButtonTypeSystem
    SYSTEM_BUTTON = 1
    # UIControlStateNormal
    NORMAL = 0
    # UIControlEventTouchUpInside
    TOUCH_UP_INSIDE = 1 << 6
    # UIControlEventEditingDidEndOnExit, the keyboard's return key
    RETURN_KEY = 1 << 19
    # UILayoutConstraintAxisVertical
    VERTICAL = 1
    # UITableViewRowAnimationFade
    FADE = 0

    # The table's rows, which UIKit asks for as it draws them.
    class Rows < ObjC::NSObject
      objc_protocols "UITableViewDataSource"

      # The List the rows show.
      attr_accessor :list

      objc_method("tableView:numberOfRowsInSection:") { |_table, _section| list.items.size }

      objc_method("tableView:cellForRowAtIndexPath:") do |table, path|
        cell = table.dequeueReusableCellWithIdentifier("item", forIndexPath: path)
        content = cell.defaultContentConfiguration
        content.text = list.items.fetch(path.row)
        cell.contentConfiguration = content
        cell
      end

      objc_method("tableView:commitEditingStyle:forRowAtIndexPath:") do |table, _style, path|
        item = list.remove(path.row)
        table.deleteRowsAtIndexPaths([path], withRowAnimation: FADE)
        puts "Basket removed #{item}"
      end
    end

    # What the Add button and the keyboard's return key do.
    class Actions < ObjC::NSObject
      # The Screen whose controls these are.
      attr_accessor :screen

      objc_method("add:") { |_sender| screen.add }
    end

    # The screen's views, and what adding an item does to them.
    class Screen
      # The navigation controller the screen's views are in.
      attr_reader :controller

      # The screen of +list+, a List.
      def initialize(list)
        @list = list
        @rows = Rows.new.tap { |rows| rows.list = list }
        @actions = Actions.new.tap { |actions| actions.screen = self }
        content = ObjC::UIViewController.new
        content.title = "Basket"
        content.view.backgroundColor = ObjC::UIColor.systemBackgroundColor
        place(content.view, column)
        @controller = ObjC::UINavigationController.alloc.initWithRootViewController(content)
        @controller.navigationBar.prefersLargeTitles = true
      end

      # Adds what the field holds, and empties the field.
      def add
        item = @list.add(@field.text.to_s) or return

        @field.text = ""
        @table.reloadData
        puts "Basket added #{item}"
      end

      # How many rows the table shows, as UIKit asks Rows.
      def rows
        @table.numberOfRowsInSection(0)
      end

      private def column
        stack = ObjC::UIStackView.alloc.initWithArrangedSubviews([entry, table])
        stack.axis = VERTICAL
        stack.spacing = 8.0
        stack
      end

      private def entry
        @field = ObjC::UITextField.new
        @field.placeholder = "Add an item"
        @field.borderStyle = ROUNDED_RECT
        @field.addTarget(@actions, action: "add:", forControlEvents: RETURN_KEY)
        button = ObjC::UIButton.buttonWithType(SYSTEM_BUTTON)
        button.setTitle("Add", forState: NORMAL)
        button.addTarget(@actions, action: "add:", forControlEvents: TOUCH_UP_INSIDE)
        row = ObjC::UIStackView.alloc.initWithArrangedSubviews([@field, button])
        row.spacing = 8.0
        row
      end

      private def table
        @table = ObjC::UITableView.new
        @table.registerClass(ObjC::UITableViewCell, forCellReuseIdentifier: "item")
        @table.dataSource = @rows
        @table
      end

      # Puts +column+ in +view+, within the margins Apple's guidelines
      # give a screen's content, and above the home indicator.
      private def place(view, column)
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        margins = view.layoutMarginsGuide
        safe = view.safeAreaLayoutGuide
        ObjC::NSLayoutConstraint.activateConstraints([
          column.topAnchor.constraintEqualToAnchor(safe.topAnchor, constant: 8.0),
          column.bottomAnchor.constraintEqualToAnchor(safe.bottomAnchor),
          column.leadingAnchor.constraintEqualToAnchor(margins.leadingAnchor),
          column.trailingAnchor.constraintEqualToAnchor(margins.trailingAnchor),
        ])
      end
    end

    # Runs Basket: hands the main thread to UIKit, which then asks the
    # scene delegate for the window, where Screen goes.
    def self.run(list)
      SceneDelegate.list = list
      ObjC.application_main(AppDelegate)
    end
  end
end

# The application's delegate, which UIApplicationMain makes.
class AppDelegate < Fledge::ObjC::UIResponder
  objc_protocols "UIApplicationDelegate"

  objc_method("application:didFinishLaunchingWithOptions:") { |_application, _options| true }
end

# The scene's delegate, which Info.plist names, and which puts Basket's
# screen in the scene's window.
class SceneDelegate < Fledge::ObjC::UIResponder
  objc_protocols "UIWindowSceneDelegate"

  class << self
    # The List each scene's screen shows.
    attr_accessor :list
  end

  objc_method("scene:willConnectToSession:options:") do |scene, _session, _options|
    screen = Basket::IOS::Screen.new(SceneDelegate.list)
    @window = Fledge::ObjC::UIWindow.alloc.initWithWindowScene(scene)
    @window.rootViewController = screen.controller
    @window.makeKeyAndVisible
    @screen = screen
    rows = screen.rows
    puts "Basket shows #{rows} #{(rows == 1) ? 'item' : 'items'}"
  end
end
