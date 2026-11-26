# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "android/activities"
require_relative "android/listener"

module Basket
  # Basket's screen on Android, drawn by Android's own views: a text
  # field with an Add button above a list, under the app bar. The
  # keyboard's Done key, or Enter, adds the item, as the Add button
  # does, and a long press on an item removes it. Each object is
  # Android's own, made and called as Android's reference documents it,
  # through android/java.rb, which this app carries in Ruby: Android's
  # runtime gives an app's Ruby nothing else to reach Java with.
  module Android
    # Shorter names for the classes this screen makes, by their Java names.
    LinearLayout = Java::Klass["android.widget.LinearLayout"]
    # A view's place in a LinearLayout.
    LayoutParams = Java::Klass["android.widget.LinearLayout$LayoutParams"]
    # A field the person types in.
    EditText = Java::Klass["android.widget.EditText"]
    # A button.
    Button = Java::Klass["android.widget.Button"]
    # A list that scrolls.
    ListView = Java::Klass["android.widget.ListView"]
    # What a ListView shows, from a Java list.
    ArrayAdapter = Java::Klass["android.widget.ArrayAdapter"]
    # Java's list, which the adapter reads.
    ArrayList = Java::Klass["java.util.ArrayList"]
    # What a field tells the keyboard, such as which action its Enter key
    # shows.
    EditorInfo = Java::Klass["android.view.inputmethod.EditorInfo"]
    # Android's own layouts, such as a list's row of one line.
    Layouts = Java::Klass["android.R$layout"]
    # Android's loop of messages, which every tap and key arrives from.
    Looper = Java::Klass["android.os.Looper"]

    # The screen's views on +activity+, and what adding and removing an
    # item does to them.
    class Screen
      # The activity whose screen this is.
      attr_reader :activity

      # The text field a person types an item in.
      attr_reader :field

      # Draws +list+, a List, on +activity+.
      def initialize(activity, list)
        @activity = activity
        @list = list
        @items = ArrayList.new
        list.items.each { |item| @items.add(item) }
        @adapter = ArrayAdapter.new(activity, Layouts.simple_list_item_1, @items)
        column = LinearLayout.new(activity)
        column.setOrientation(LinearLayout.VERTICAL)
        column.setFitsSystemWindows(true)
        column.addView(entry)
        column.addView(list_view, LayoutParams.new(LayoutParams.MATCH_PARENT, 0, 1.0))
        activity.setTitle("Basket")
        activity.setContentView(column)
      end

      # Adds what the field holds, and empties the field.
      def add
        item = @list.add(@field.getText.to_s) or return

        @adapter.add(item)
        @field.setText("")
        puts "Basket added #{item}"
      end

      # Removes the item at +position+.
      def remove(position)
        item = @list.remove(position)
        @items.remove(position)
        @adapter.notifyDataSetChanged
        puts "Basket removed #{item}"
      end

      # Runs +block+ once the list is laid out, from Android's loop.
      def once_shown(&block)
        @view.post(Listener.implement(["java.lang.Runnable"], run: block))
      end

      # How many items the list shows, as its adapter tells it.
      def rows
        @view.getCount
      end

      private def entry
        @field = EditText.new(activity)
        @field.setHint("Add an item")
        @field.setSingleLine(true)
        @field.setImeOptions(EditorInfo.IME_ACTION_DONE)
        @field.setOnEditorActionListener(Listener.implement(["android.widget.TextView$OnEditorActionListener"],
          onEditorAction: -> (_view, _action, _event) { add || true }))
        button = Button.new(activity)
        button.setText("Add")
        button.setOnClickListener(Listener.implement(["android.view.View$OnClickListener"], onClick: -> (_view) { add }))
        row = LinearLayout.new(activity)
        row.addView(@field, LayoutParams.new(0, LayoutParams.WRAP_CONTENT, 1.0))
        row.addView(button)
        row
      end

      private def list_view
        @view = ListView.new(activity)
        @view.setAdapter(@adapter)
        @view.setOnItemLongClickListener(Listener.implement(["android.widget.AdapterView$OnItemLongClickListener"],
          onItemLongClick: -> (_parent, _view, position, _id) { remove(position) || true }))
        @view
      end
    end

    # Runs Basket: draws its screen on the activity Android made first,
    # and again on each activity Android makes in its place, as it does
    # when the phone turns, then runs Android's loop of messages, which
    # delivers every tap and key to the listeners above.
    def self.run(list)
      screen = Screen.new(Activities.first, list)
      Activities.application.registerActivityLifecycleCallbacks(Listener.implement(["android.app.Application$ActivityLifecycleCallbacks"],
        onActivityStarted: -> (activity) { screen = Screen.new(activity, list) unless activity == screen.activity }))
      screen.once_shown do
        rows = screen.rows
        puts "Basket shows #{rows} #{(rows == 1) ? 'item' : 'items'}"
      end
      Looper.loop
    end
  end
end
