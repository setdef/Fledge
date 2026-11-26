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
  # through the JNI calls of android/java.rb, which this app carries in
  # Ruby: Android's runtime gives an app's Ruby nothing else to reach
  # Java with.
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
        @items = ArrayList.new("()V")
        list.items.each { |item| @items.call("add", "(Ljava/lang/Object;)Z", item) }
        @adapter = ArrayAdapter.new("(Landroid/content/Context;ILjava/util/List;)V", activity, Layouts.int("simple_list_item_1"), @items)
        column = LinearLayout.new("(Landroid/content/Context;)V", activity)
        column.call("setOrientation", "(I)V", LinearLayout.int("VERTICAL"))
        column.call("setFitsSystemWindows", "(Z)V", true)
        column.call("addView", "(Landroid/view/View;)V", entry)
        column.call("addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V", list_view,
          LayoutParams.new("(IIF)V", LayoutParams.int("MATCH_PARENT"), 0, 1.0))
        activity.call("setTitle", "(Ljava/lang/CharSequence;)V", "Basket")
        activity.call("setContentView", "(Landroid/view/View;)V", column)
      end

      # Adds what the field holds, and empties the field.
      def add
        item = @list.add(@field.call("getText", "()Landroid/text/Editable;").to_s) or return

        @adapter.call("add", "(Ljava/lang/Object;)V", item)
        @field.call("setText", "(Ljava/lang/CharSequence;)V", "")
        puts "Basket added #{item}"
      end

      # Removes the item at +position+.
      def remove(position)
        item = @list.remove(position)
        @items.call("remove", "(I)Ljava/lang/Object;", position)
        @adapter.call("notifyDataSetChanged", "()V")
        puts "Basket removed #{item}"
      end

      # Runs +block+ once the list is laid out, from Android's loop.
      def once_shown(&block)
        @view.call("post", "(Ljava/lang/Runnable;)Z", Listener.implement(["java.lang.Runnable"], run: block))
      end

      # How many items the list shows, as its adapter tells it.
      def rows
        @view.call("getCount", "()I")
      end

      private def entry
        @field = EditText.new("(Landroid/content/Context;)V", activity)
        @field.call("setHint", "(Ljava/lang/CharSequence;)V", "Add an item")
        @field.call("setSingleLine", "(Z)V", true)
        @field.call("setImeOptions", "(I)V", EditorInfo.int("IME_ACTION_DONE"))
        @field.call("setOnEditorActionListener", "(Landroid/widget/TextView$OnEditorActionListener;)V",
          Listener.implement(["android.widget.TextView$OnEditorActionListener"],
            onEditorAction: -> (_view, _action, _event) { add || true }))
        button = Button.new("(Landroid/content/Context;)V", activity)
        button.call("setText", "(Ljava/lang/CharSequence;)V", "Add")
        button.call("setOnClickListener", "(Landroid/view/View$OnClickListener;)V",
          Listener.implement(["android.view.View$OnClickListener"], onClick: -> (_view) { add }))
        row = LinearLayout.new("(Landroid/content/Context;)V", activity)
        row.call("addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V", @field,
          LayoutParams.new("(IIF)V", 0, LayoutParams.int("WRAP_CONTENT"), 1.0))
        row.call("addView", "(Landroid/view/View;)V", button)
        row
      end

      private def list_view
        @view = ListView.new("(Landroid/content/Context;)V", activity)
        @view.call("setAdapter", "(Landroid/widget/ListAdapter;)V", @adapter)
        @view.call("setOnItemLongClickListener", "(Landroid/widget/AdapterView$OnItemLongClickListener;)V",
          Listener.implement(["android.widget.AdapterView$OnItemLongClickListener"],
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
      Activities.application.call("registerActivityLifecycleCallbacks", "(Landroid/app/Application$ActivityLifecycleCallbacks;)V",
        Listener.implement(["android.app.Application$ActivityLifecycleCallbacks"],
          onActivityStarted: -> (activity) { screen = Screen.new(activity, list) unless activity == screen.activity }))
      screen.once_shown do
        rows = screen.rows
        puts "Basket shows #{rows} #{(rows == 1) ? 'item' : 'items'}"
      end
      Looper.call("loop", "()V")
    end
  end
end
