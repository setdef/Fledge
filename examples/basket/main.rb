# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket, a shopping list for iOS, iPadOS, Android, Linux, and Windows:
# type an item, add it, and remove it once it is in the cart. Each draws
# it with that system's widgets, UIKit's on iOS, Android's views on
# Android, GTK 4 with libadwaita on Linux, and Win32's common controls on
# Windows, which this Ruby makes and drives: on iOS through
# lib/basket/objc.rb, Basket's few lines over Fiddle, which Ruby bundles,
# on Android through lib/basket/android/, Basket's calls into Java over
# Fiddle, zlib, and digest, which Ruby bundles too, on Linux through
# lib/basket/gtk.rb, Basket's calls into GTK's C API over Fiddle, and on
# Windows through lib/basket/win32.rb, Basket's calls into user32 and
# comctl32 over Fiddle. fledge.yml says kind: windowed, so the app's Ruby
# runs on the thread those widgets belong to, and on Windows runs without
# a console.

require_relative "lib/basket/list"

# The list's file, among the app's own: an iOS app keeps its files in
# Documents, and an Android app in its files folder, which is HOME.
documents = File.join(Dir.home, "Documents")
list = Basket::List.new(File.join(File.directory?(documents) ? documents : Dir.home, "basket.json"))

# Whether this Ruby runs on an iPhone or iPad: on a system whose
# Objective-C runtime has UIKit to load, which a Mac does not.
ios = RUBY_PLATFORM.include?("darwin") && begin
  require_relative "lib/basket/objc"
  Basket::ObjC.load_framework("UIKit")
end

if ios
  require_relative "lib/basket/ios"
  Basket::IOS.run(list)
elsif RUBY_PLATFORM.include?("android")
  require_relative "lib/basket/android"
  Basket::Android.run(list)
elsif RUBY_PLATFORM.include?("linux")
  require_relative "lib/basket/linux"
  exit Basket::Linux.run(list)
elsif Gem.win_platform?
  require_relative "lib/basket/windows"
  Basket::Windows.run(list)
else
  abort "Basket is for iOS, Android, Linux, and Windows: build it with fledge build ios, fledge build android, or fledge build on Linux or Windows."
end
