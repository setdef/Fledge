# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "gtk"

module Basket
  # Basket's screen on Linux, drawn by GTK 4 and libadwaita as GNOME's
  # Human Interface Guidelines have it: a header bar, an entry with a
  # suggested-action Add button beside it, and a boxed list whose rows
  # each have a button that removes them, after which a toast offers to
  # undo it. Return in the entry adds, as the Add button does. Each
  # widget is one GTK makes, called as GTK documents it, through
  # Basket::GTK, which is Fiddle, a library Ruby bundles, and nothing
  # else.
  module Linux
    # GtkOrientation's GTK_ORIENTATION_HORIZONTAL
    HORIZONTAL = 0
    # GTK_ORIENTATION_VERTICAL
    VERTICAL = 1
    # GtkAlign's GTK_ALIGN_START
    START = 1
    # GTK_ALIGN_CENTER
    CENTER = 3
    # GtkSelectionMode's GTK_SELECTION_NONE
    SELECTION_NONE = 0
    # The number of SIGINT, which a terminal's Ctrl-C sends
    INTERRUPT = 2
    # The number of SIGTERM, which +kill+ sends
    TERMINATE = 15

    # The screen's widgets, and what adding and removing an item does to
    # them.
    class Screen
      # The entry a person types an item in.
      attr_reader :entry

      # The screen of +list+, a List, in a window of +application+.
      def initialize(application, list)
        @list = list
        @removed = []
        @add = proc { |_widget, _data| add }
        @remove = proc { |_button, row| remove(row) }
        @undo = proc { |_toast, number| restore(number) }
        @overlay = GTK.adw_toast_overlay_new
        window = GTK.adw_application_window_new(application)
        GTK.gtk_window_set_title(window, "Basket")
        GTK.gtk_window_set_default_size(window, 400, 520)
        GTK.adw_application_window_set_content(window, content)
        @list.items.each { |item| append(item) }
        GTK.gtk_window_present(window)
        GTK.gtk_widget_grab_focus(@entry)
      end

      # Adds what the entry holds, and empties the entry.
      def add
        item = @list.add(GTK.gtk_editable_get_text(@entry)) or return

        GTK.gtk_editable_set_text(@entry, "")
        append(item)
        puts "Basket added #{item}"
      end

      # Removes the item of +row+, a GtkListBoxRow, and offers to undo it.
      def remove(row)
        item = @list.remove(GTK.gtk_list_box_row_get_index(row))
        GTK.gtk_list_box_remove(@box, row)
        puts "Basket removed #{item}"
        @removed << item
        toast = GTK.adw_toast_new("Removed #{item}")
        GTK.adw_toast_set_button_label(toast, "Undo")
        GTK.connect(toast, "button-clicked", @removed.size - 1, &@undo)
        GTK.adw_toast_overlay_add_toast(@overlay, toast)
      end

      # The row at +index+, a GtkListBoxRow, which is null past the last.
      def row(index)
        GTK.gtk_list_box_get_row_at_index(@box, index)
      end

      # How many rows the list shows.
      def rows
        (0..).find { |index| row(index).null? }
      end

      private def restore(number)
        item = @list.add(@removed.fetch(number))
        append(item)
        puts "Basket restored #{item}"
      end

      # The header bar above the toast overlay, which holds the column.
      private def content
        column = GTK.gtk_box_new(VERTICAL, 12)
        margin(column, 12)
        GTK.gtk_box_append(column, entry_row)
        GTK.gtk_box_append(column, list_view)
        GTK.adw_toast_overlay_set_child(@overlay, column)
        GTK.gtk_widget_set_vexpand(@overlay, 1)
        content = GTK.gtk_box_new(VERTICAL, 0)
        GTK.gtk_box_append(content, GTK.adw_header_bar_new)
        GTK.gtk_box_append(content, @overlay)
        content
      end

      private def entry_row
        @entry = GTK.gtk_entry_new
        GTK.gtk_widget_set_hexpand(@entry, 1)
        GTK.set_string_property(@entry, "placeholder-text", "Add an item…")
        GTK.connect(@entry, "activate", &@add)
        button = GTK.gtk_button_new_with_label("Add")
        GTK.gtk_widget_add_css_class(button, "suggested-action")
        GTK.connect(button, "clicked", &@add)
        row = GTK.gtk_box_new(HORIZONTAL, 6)
        GTK.gtk_box_append(row, @entry)
        GTK.gtk_box_append(row, button)
        row
      end

      private def list_view
        @box = GTK.gtk_list_box_new
        GTK.gtk_list_box_set_selection_mode(@box, SELECTION_NONE)
        GTK.gtk_widget_add_css_class(@box, "boxed-list")
        GTK.gtk_widget_set_valign(@box, START)
        GTK.gtk_list_box_set_placeholder(@box, empty)
        scrolled = GTK.gtk_scrolled_window_new
        GTK.gtk_widget_set_vexpand(scrolled, 1)
        GTK.gtk_scrolled_window_set_child(scrolled, @box)
        scrolled
      end

      # What the list shows with no rows.
      private def empty
        label = GTK.gtk_label_new("Nothing in the basket")
        GTK.gtk_widget_add_css_class(label, "dim-label")
        GTK.gtk_widget_set_margin_top(label, 24)
        label
      end

      private def append(item)
        label = GTK.gtk_label_new(item)
        GTK.gtk_label_set_xalign(label, 0.0)
        GTK.gtk_widget_set_hexpand(label, 1)
        GTK.gtk_widget_set_valign(label, CENTER)
        button = GTK.gtk_button_new_from_icon_name("user-trash-symbolic")
        GTK.gtk_widget_add_css_class(button, "flat")
        GTK.gtk_widget_set_tooltip_text(button, "Remove #{item}")
        GTK.gtk_widget_set_valign(button, CENTER)
        line = GTK.gtk_box_new(HORIZONTAL, 12)
        margin(line, 6)
        GTK.gtk_box_append(line, label)
        GTK.gtk_box_append(line, button)
        row = GTK.gtk_list_box_row_new
        GTK.gtk_list_box_row_set_child(row, line)
        GTK.gtk_list_box_append(@box, row)
        GTK.connect(button, "clicked", row, &@remove)
      end

      private def margin(widget, size)
        GTK.gtk_widget_set_margin_top(widget, size)
        GTK.gtk_widget_set_margin_bottom(widget, size)
        GTK.gtk_widget_set_margin_start(widget, size)
        GTK.gtk_widget_set_margin_end(widget, size)
      end
    end

    # Runs Basket: GTK's main loop on this, the main thread, until the
    # window closes or the process gets SIGINT or SIGTERM, and returns
    # its status. A computer without GTK 4 or libadwaita gets a message
    # that says which, and status 72, which is what the launcher exits
    # with for a library that is missing.
    def self.run(list)
      GTK.load
      $stdout.sync = true
      application = GTK.adw_application_new("com.setdef.fledge.Basket", 0)
      screens = []
      GTK.connect(application, "activate") do |instance, _data|
        screens << Screen.new(instance, list)
        rows = screens.last.rows
        puts "Basket shows #{rows} #{(rows == 1) ? 'item' : 'items'}"
      end
      [INTERRUPT, TERMINATE].each do |signal|
        GTK.on_unix_signal(signal) { GTK.g_application_quit(application) }
      end
      status = GTK.g_application_run(application, 0, nil)
      GTK.g_object_unref(application)
      status
    rescue GTK::Missing => e
      warn e.message
      72
    end
  end
end
