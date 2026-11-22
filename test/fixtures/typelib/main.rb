# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The typelib probe: an app over ruby-gnome's gdk_pixbuf2, which has no
# compiled file of its own and loads GDK-PixBuf through GObject
# introspection. Requiring it loads the GdkPixbuf-2.0 typelib, and the
# GLib, GObject, GModule, and Gio typelibs that one needs, by name, from
# wherever libgirepository finds them; then the app makes an image in
# memory, which needs no window and no file.

require "gdk_pixbuf2"

pixbuf = GdkPixbuf::Pixbuf.new(width: 2, height: 3, has_alpha: true)
puts "GdkPixbuf #{pixbuf.width}x#{pixbuf.height}, #{pixbuf.n_channels} channels"
