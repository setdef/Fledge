# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0

require "fledge/jni"

module Basket
  # Basket's screen on Android, drawn by Android's own views: a text
  # field with an Add button above a list, under the app bar. A long
  # press on an item removes it. Each object is Android's own, made and
  # called as Android documents it, through Fledge::JNI.
  module Android
    # The runtime's bridge to Java.
    JNI = Fledge::JNI
    # Android's classes this screen makes, by their Java names.
    LinearLayout = JNI.import("android.widget.LinearLayout")
    # A view's place in a LinearLayout.
    LayoutParams = JNI.import("android.widget.LinearLayout$LayoutParams")
    # A field the person types in.
    EditText = JNI.import("android.widget.EditText")
    # A button.
    Button = JNI.import("android.widget.Button")
    # A list that scrolls.
    ListView = JNI.import("android.widget.ListView")
    # What a ListView shows, from a Java list.
    ArrayAdapter = JNI.import("android.widget.ArrayAdapter")
    # Java's list, which the adapter reads.
    ArrayList = JNI.import("java.util.ArrayList")
    # Android's own layouts, such as a list's row of one line.
    Layouts = JNI.import("android.R$layout")

    # The screen's views on +activity+, and what adding and removing an
    # item does to them.
    class Screen
      # The activity whose screen this is.
      attr_reader :activity

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
        item = @field.getText.to_s.strip
        return if item.empty?

        @list.add(item)
        @adapter.add(item)
        @field.setText("")
      end

      # Removes the item at +position+.
      def remove(position)
        @list.remove(position)
        @items.remove(position)
        @adapter.notifyDataSetChanged
      end

      # Runs +block+ once the list is laid out, from Android's loop.
      def once_shown(&block)
        @view.post(JNI.implement("java.lang.Runnable", run: block))
      end

      # How many items the list shows, as its adapter tells it.
      def rows
        @view.getCount
      end

      private def entry
        @field = EditText.new(activity)
        @field.setHint("Add an item")
        @field.setSingleLine(true)
        @field.setOnEditorActionListener(JNI.implement("android.widget.TextView$OnEditorActionListener",
          onEditorAction: -> (_view, _action, _event) { add || true }))
        button = Button.new(activity)
        button.setText("Add")
        button.setOnClickListener(JNI.implement("android.view.View$OnClickListener", onClick: -> (_view) { add }))
        row = LinearLayout.new(activity)
        row.addView(@field, LayoutParams.new(0, LayoutParams.WRAP_CONTENT, 1.0))
        row.addView(button)
        row
      end

      private def list_view
        @view = ListView.new(activity)
        @view.setAdapter(@adapter)
        @view.setOnItemLongClickListener(JNI.implement("android.widget.AdapterView$OnItemLongClickListener",
          onItemLongClick: -> (_parent, _view, position, _id) { remove(position) || true }))
        @view
      end
    end

    # Runs Basket: draws its screen on the activity that started its Ruby,
    # and again on each activity Android makes in its place, as it does
    # when the phone turns, then hands the main thread back to Android.
    def self.run(list)
      screen = Screen.new(JNI.import("org.setdef.fledge.FledgeRuby").activity, list)
      screen.activity.getApplication.registerActivityLifecycleCallbacks(
        JNI.implement("android.app.Application$ActivityLifecycleCallbacks",
          onActivityStarted: -> (activity) { screen = Screen.new(activity, list) unless activity == screen.activity }),
      )
      screen.once_shown do
        rows = screen.rows
        puts "Basket shows #{rows} #{(rows == 1) ? 'item' : 'items'}"
      end
      JNI.loop
    end
  end
end
