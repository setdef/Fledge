# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The LibUI probe: a window of the operating system's own toolkit,
# through a third party's GUI gem.
#
# LibUI binds libui-ng, which draws with AppKit on macOS, GTK 3 on
# Linux, and Win32 on Windows, through Fiddle, and its precompiled gems
# carry libui-ng's library. This app opens a window with a line of text
# in it, and stays until the person closes it.
#
# Given a path, it writes there as JSON, once the window has been shown
# for a second, what it ran on, which library LibUI opened, and the
# window's title and the size its toolkit gave its content, then closes
# the window and exits. CI starts it that way, as nobody can watch it,
# and reads the report (.github/scripts/deliver-libui.sh).
#
#   ruby main.rb [REPORT]

require "json"
require "libui"

report = ARGV[0]
LibUI.init
window = LibUI.new_window("Hello LibUI", 320, 120, 0)
LibUI.window_set_child(window, LibUI.new_label("Hello from Ruby, through libui-ng"))
LibUI.window_on_closing(window) do
  LibUI.quit
  1
end
LibUI.control_show(window)

if report
  LibUI.timer(1000) do
    width, height = Array.new(2) { Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE) }
    LibUI.window_content_size(window, width, height)
    # libui-ng's text is the caller's to free, and its uninit reports
    # (and on Windows exits 3 for) any it was not given back.
    text = LibUI.window_title(window)
    title = text.to_s
    LibUI.free_text(text)
    facts = {
      "ruby" => RUBY_VERSION,
      "platform" => RUBY_PLATFORM,
      "libui" => LibUI::VERSION,
      "library" => File.basename(LibUI.ffi_lib),
      "title" => title,
      "visible" => LibUI.control_visible(window) == 1,
      "content" => [width, height].map { |size| size[0, Fiddle::SIZEOF_INT].unpack1("i") },
    }
    File.write(report, "#{JSON.generate(facts)}\n")
    LibUI.control_destroy(window)
    LibUI.quit
    0
  end
end

LibUI.main
LibUI.uninit
