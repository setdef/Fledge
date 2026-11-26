# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "fiddle"

module Basket
  # Basket's calls into GTK 4 and libadwaita, which are C libraries: each
  # function Basket's screen uses is declared below as its header
  # declares it, and called by the name the C API gives it, as
  # <tt>GTK.gtk_box_new(1, 12)</tt>. It is Fiddle, a library Ruby bundles,
  # and nothing else, so it runs under any +ruby+ on a computer that has
  # the two libraries.
  module GTK
    # Raised when this computer lacks a library Basket's screen draws with.
    class Missing < LoadError; end

    # The library of GTK 4, opened by soname as a C program linked to it
    # would have it. Its handle finds GLib's, GObject's, and GIO's
    # functions too, since +dlsym+ searches a library's dependencies.
    GTK_SONAME = "libgtk-4.so.1"

    # The library of libadwaita, whose functions begin with +adw_+.
    ADWAITA_SONAME = "libadwaita-1.so.0"

    # Every function Basket calls: a C prototype's name, parameter types,
    # and result. A +string+ result is the C string it points to.
    PROTOTYPES = <<~C
      adw_init()
      adw_application_new(pointer, int) -> pointer
      adw_application_window_new(pointer) -> pointer
      adw_application_window_set_content(pointer, pointer)
      adw_header_bar_new() -> pointer
      adw_toast_overlay_new() -> pointer
      adw_toast_overlay_set_child(pointer, pointer)
      adw_toast_overlay_add_toast(pointer, pointer)
      adw_toast_new(pointer) -> pointer
      adw_toast_set_button_label(pointer, pointer)
      g_application_run(pointer, int, pointer) -> int
      g_application_quit(pointer)
      g_object_unref(pointer)
      g_signal_connect_data(pointer, pointer, pointer, pointer, pointer, int) -> long
      g_unix_signal_add(int, pointer, pointer) -> int
      gtk_box_new(int, int) -> pointer
      gtk_box_append(pointer, pointer)
      gtk_button_new_from_icon_name(pointer) -> pointer
      gtk_button_new_with_label(pointer) -> pointer
      gtk_editable_get_text(pointer) -> string
      gtk_editable_set_text(pointer, pointer)
      gtk_entry_new() -> pointer
      gtk_label_new(pointer) -> pointer
      gtk_label_set_xalign(pointer, float)
      gtk_list_box_new() -> pointer
      gtk_list_box_append(pointer, pointer)
      gtk_list_box_remove(pointer, pointer)
      gtk_list_box_get_row_at_index(pointer, int) -> pointer
      gtk_list_box_row_new() -> pointer
      gtk_list_box_row_set_child(pointer, pointer)
      gtk_list_box_row_get_index(pointer) -> int
      gtk_list_box_set_placeholder(pointer, pointer)
      gtk_list_box_set_selection_mode(pointer, int)
      gtk_scrolled_window_new() -> pointer
      gtk_scrolled_window_set_child(pointer, pointer)
      gtk_widget_add_css_class(pointer, pointer)
      gtk_widget_grab_focus(pointer) -> int
      gtk_widget_set_hexpand(pointer, int)
      gtk_widget_set_margin_bottom(pointer, int)
      gtk_widget_set_margin_end(pointer, int)
      gtk_widget_set_margin_start(pointer, int)
      gtk_widget_set_margin_top(pointer, int)
      gtk_widget_set_tooltip_text(pointer, pointer)
      gtk_widget_set_valign(pointer, int)
      gtk_widget_set_vexpand(pointer, int)
      gtk_window_present(pointer)
      gtk_window_set_default_size(pointer, int, int)
      gtk_window_set_title(pointer, pointer)
    C

    # The Fiddle type of each type name a prototype uses.
    TYPES = {
      "int" => Fiddle::TYPE_INT,
      "long" => Fiddle::TYPE_LONG,
      "float" => Fiddle::TYPE_FLOAT,
      "pointer" => Fiddle::TYPE_VOIDP,
      "string" => Fiddle::TYPE_VOIDP,
      "void" => Fiddle::TYPE_VOID,
    }.freeze

    # g_object_set is variadic, so Fiddle takes its extra arguments as a
    # type and a value each.
    OBJECT_SET = [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VARIADIC].freeze

    @closures = {}.compare_by_identity
    @signal_closures = []

    class << self
      # Opens GTK 4 and libadwaita, and makes each function of
      # PROTOTYPES a method of GTK. Raises Missing, saying which library
      # this computer lacks. Calling it again does nothing.
      def load
        return true if @functions

        handles = [GTK_SONAME, ADWAITA_SONAME].to_h do |soname|
          [soname, Fiddle.dlopen(soname)]
        rescue Fiddle::DLError => e
          raise Missing, "Basket needs #{soname}, which this computer does not have (#{e.message})"
        end
        @functions = PROTOTYPES.each_line.to_h { |line| bind(line, handles) }
        @set_object = Fiddle::Function.new(handles.fetch(GTK_SONAME)["g_object_set"], OBJECT_SET, Fiddle::TYPE_VOID)
        true
      end

      # Whether this computer has the libraries.
      def available?
        load
      rescue Missing
        false
      end

      # Calls the function +name+, which PROTOTYPES declares.
      def method_missing(name, *)
        function = @functions&.fetch(name) { nil }
        return super unless function

        function.call(*)
      end

      # Whether +name+ is a function of PROTOTYPES, once GTK is loaded.
      def respond_to_missing?(name, include_private = false)
        @functions&.key?(name) || super
      end

      # Sets the string property +property+ of +object+, as
      # <tt>g_object_set (object, property, value, NULL)</tt> does.
      def set_string_property(object, property, value)
        @set_object.call(object, property, Fiddle::TYPE_VOIDP, value, Fiddle::TYPE_VOIDP, nil)
      end

      # Connects +handler+ to +signal+ of +instance+. GTK calls it with
      # the instance and +data+, a pointer or nil, and a handler's
      # closure lives as long as the handler does: connect one handler
      # to every instance it serves.
      def connect(instance, signal, data = nil, &handler)
        closure = (@closures[handler] ||= Fiddle::Closure::BlockCaller.new(
          Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], &handler
        ))
        g_signal_connect_data(instance, signal, closure, data, nil, 0)
      end

      # Runs +handler+ in GTK's main loop when this process gets the
      # Unix signal +number+. Ruby runs its signal handlers only when
      # its main thread is in Ruby, and inside g_application_run it is
      # not.
      def on_unix_signal(number, &handler)
        closure = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_VOIDP]) do |_data|
          handler.call
          0
        end
        @signal_closures << closure
        g_unix_signal_add(number, closure, nil)
      end

      private def bind(prototype, handles)
        name, parameters, result = prototype.match(/\A(\w+)\(([^)]*)\)(?: -> (\w+))?\Z/).captures
        soname = name.start_with?("adw_") ? ADWAITA_SONAME : GTK_SONAME
        function = Fiddle::Function.new(
          handles.fetch(soname)[name],
          parameters.split(", ").map { |type| TYPES.fetch(type) },
          TYPES.fetch(result || "void"),
        )
        callable = (result == "string") ? lambda { |*arguments| text(function.call(*arguments)) } : function
        [name.to_sym, callable]
      end

      private def text(pointer)
        Fiddle::Pointer.new(pointer.to_i).to_s.force_encoding(Encoding::UTF_8)
      end
    end
  end
end
