# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket, a shopping list for iOS, iPadOS, and Android: type an item,
# add it, and remove it once it is in the cart. Each phone draws it with
# its own widgets, UIKit's on iOS and Android's views on Android, which
# this Ruby makes and drives: on iOS through lib/basket/objc.rb, Basket's
# few lines over Fiddle, which Ruby bundles, and on Android through
# lib/basket/android/, Basket's calls into Java over Fiddle, zlib, and
# digest, which Ruby bundles too. fledge.yml says kind: windowed, so the
# app's Ruby runs on the thread those widgets belong to.

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
else
  abort "Basket is a phone app: build it with fledge build ios or fledge build android."
end
