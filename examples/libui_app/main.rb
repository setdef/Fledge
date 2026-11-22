# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Focus Timer: a work timer in a window of the operating system's own
# toolkit, through LibUI.
#
# LibUI binds libui-ng, which draws with AppKit on macOS, GTK 3 on
# Linux, and Win32 on Windows. The main window counts down a stretch of
# focused work, then a break, then work again (timer.rb), with a
# progress bar and a button to start or pause. The Timer menu does the
# same, and opens the settings window (on macOS, the app menu's
# Preferences), whose form sets how long each stretch lasts, what you
# are working on, what happens when time is up, and whether the next
# stretch starts by itself. Closing the main window quits.
#
#   ruby main.rb

require "libui"
require_relative "timer"

# LibUI, by the short name LibUI's own README gives it.
UI = LibUI

timer = Timer.new
task = ""
message = true

UI.init

# libui-ng's menus must exist before its first window does.
menu = UI.new_menu("Timer")
toggle_item = UI.menu_append_item(menu, "Start or Pause")
reset_item = UI.menu_append_item(menu, "Reset")
UI.menu_append_separator(menu)
settings_item = UI.menu_append_preferences_item(menu)
UI.menu_append_quit_item(menu)

window = UI.new_window("Focus Timer", 320, 160, 1)
UI.window_set_margined(window, 1)
heading = UI.new_label("")
clock = UI.new_label("")
progress = UI.new_progress_bar
toggle = UI.new_button("Start")
reset = UI.new_button("Reset")
buttons = UI.new_horizontal_box
UI.box_set_padded(buttons, 1)
UI.box_append(buttons, toggle, 1)
UI.box_append(buttons, reset, 1)
column = UI.new_vertical_box
UI.box_set_padded(column, 1)
[heading, clock, progress, buttons].each { |control| UI.box_append(column, control, 0) }
UI.window_set_child(window, column)

show = lambda do
  name = (timer.phase == :focus) ? "Focus" : "Break"
  doing = (timer.phase == :focus && !task.empty?) ? ": #{task}" : ""
  UI.label_set_text(heading, "#{name}#{doing}")
  UI.label_set_text(clock, timer.clock)
  UI.progress_bar_set_value(progress, timer.progress)
  UI.button_set_text(toggle, timer.running? ? "Pause" : "Start")
  UI.window_set_title(window, "Focus Timer (#{name})")
end
start_or_pause = lambda do
  timer.toggle
  show.call
end
restart = lambda do
  timer.reset
  show.call
end

UI.button_on_clicked(toggle) { start_or_pause.call }
UI.button_on_clicked(reset) { restart.call }
UI.menu_item_on_clicked(toggle_item) { start_or_pause.call }
UI.menu_item_on_clicked(reset_item) { restart.call }

# A tick each second, as long as the app runs: returning 1 keeps the
# timer.
UI.timer(1000) do
  ended = timer.tick
  show.call
  if ended && message
    UI.msg_box(window, "Time is up", (ended == :focus) ? "Time for a break." : "Back to work.")
  end
  1
end

# The settings window, a form of LibUI's input controls, made once and
# shown from the menu with the settings as they are.
preferences = UI.new_window("Settings", 360, 240, 0)
UI.window_set_margined(preferences, 1)
form = UI.new_form
UI.form_set_padded(form, 1)
focus_minutes = UI.new_spinbox(1, 120)
rest_minutes = UI.new_slider(1, 30)
task_entry = UI.new_entry
ending = UI.new_radio_buttons
UI.radio_buttons_append(ending, "Show a message")
UI.radio_buttons_append(ending, "Only change the window's title")
onward = UI.new_checkbox("Start the next stretch by itself")
save = UI.new_button("Save")
UI.form_append(form, "Focus minutes", focus_minutes, 0)
UI.form_append(form, "Break minutes", rest_minutes, 0)
UI.form_append(form, "Working on", task_entry, 0)
UI.form_append(form, "When time is up", ending, 0)
UI.form_append(form, "", onward, 0)
UI.form_append(form, "", save, 0)
UI.window_set_child(preferences, form)

UI.menu_item_on_clicked(settings_item) do
  UI.spinbox_set_value(focus_minutes, timer.focus)
  UI.slider_set_value(rest_minutes, timer.rest)
  UI.entry_set_text(task_entry, task)
  UI.radio_buttons_set_selected(ending, message ? 0 : 1)
  UI.checkbox_set_checked(onward, timer.onward ? 1 : 0)
  UI.control_show(preferences)
end

UI.button_on_clicked(save) do
  # libui-ng's text is the caller's to free.
  text = UI.entry_text(task_entry)
  task = text.to_s.strip
  UI.free_text(text)
  message = UI.radio_buttons_selected(ending).zero?
  timer.configure(focus: UI.spinbox_value(focus_minutes), rest: UI.slider_value(rest_minutes),
    onward: UI.checkbox_checked(onward) == 1)
  show.call
  UI.control_hide(preferences)
end

UI.window_on_closing(preferences) do
  UI.control_hide(preferences)
  0
end

# libui-ng reports, and on Windows exits with 3 for, any control not
# destroyed when the app ends: the main window destroys itself when its
# handler returns 1, and each handler destroys the settings window.
UI.window_on_closing(window) do
  UI.control_destroy(preferences)
  UI.quit
  1
end
UI.on_should_quit do
  UI.control_destroy(preferences)
  UI.control_destroy(window)
  1
end

show.call
UI.control_show(window)
UI.main
UI.uninit
