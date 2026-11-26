# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket, a shopping list for macOS, iOS, iPadOS, Android, Linux, and
# Windows: type an item, add it, and remove it once it is in the cart.
# Each draws it with that system's widgets, AppKit's on a Mac, UIKit's on
# iOS, Android's views on Android, GTK 4 with libadwaita on Linux, and
# WinUI 3 on a Windows that has the Windows App Runtime and Win32's
# common controls on one that has not, which this Ruby makes and drives: on
# a Mac and iOS through lib/basket/objc.rb, Basket's few lines over
# Fiddle, which Ruby bundles, on Android through lib/basket/android/,
# Basket's calls into Java over Fiddle, zlib, and digest, which Ruby
# bundles too, on Linux through lib/basket/gtk.rb, Basket's calls into
# GTK's C API over Fiddle, and on Windows through lib/basket/win32.rb,
# Basket's calls into user32 and comctl32 over Fiddle, or through
# lib/basket/winui.rb, Basket's calls into the Windows Runtime over
# Fiddle. The app's Ruby
# runs on the main thread, where those widgets are made, as under ruby
# main.rb, and fledge.yml says kind: windowed, so on Windows it runs
# without a console.

require_relative "lib/basket/data_folder"
require_relative "lib/basket/list"

# The list's file, in the folder its system keeps an app's data in, which
# Etcetera finds (lib/basket/data_folder.rb). Its path is logged, for a
# person who looks for the list.
puts "Basket keeps its list in #{Basket::DataFolder.list_path}"
list = Basket::List.new(Basket::DataFolder.list_path)

# Whether this Ruby runs on an iPhone or iPad, or on a Mac: on a system
# whose Objective-C runtime has UIKit to load, or else AppKit.
if RUBY_PLATFORM.include?("darwin")
  require_relative "lib/basket/objc"
  objc = Basket::ObjC
end
ios = objc&.load_framework("UIKit")
mac = !ios && objc&.load_framework("AppKit")

if mac
  require_relative "lib/basket/macos"
  Basket::MacOS.run(list)
elsif ios
  require_relative "lib/basket/ios"
  Basket::IOS.run(list)
elsif RUBY_PLATFORM.include?("android")
  require_relative "lib/basket/android"
  Basket::Android.run(list)
elsif RUBY_PLATFORM.include?("linux")
  require_relative "lib/basket/linux"
  exit Basket::Linux.run(list)
elsif Gem.win_platform?
  # WinUI's screen where Windows has the Windows App Runtime and WinUI
  # starts, and Win32's common controls, which every Windows has, where it
  # has not or does not.
  require_relative "lib/basket/winui"
  require_relative "lib/basket/windows"
  if Basket::WinUI.available?
    Basket::WinUI.run(list) { Basket::Windows.run(list) }
  else
    Basket::Windows.run(list)
  end
else
  abort "Basket is for macOS, iOS, Android, Linux, and Windows: build it with fledge build, fledge build ios, or fledge build android."
end
