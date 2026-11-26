# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket's tests inside the app on a phone: the list's and the data
# folder's, which also run on your own computer, the dex writer's and the calls into Java, on
# Android, the iOS bridge's, on iOS, and the screen's, which need the
# phone's widgets.
# fledge test runs this file as the app's program, in place of main.rb,
# and exits with its status, as ruby test/phone.rb would:
#
#   fledge test ios test/phone.rb
#   fledge test android test/phone.rb

require_relative "list_test"
require_relative "data_folder_test"
require_relative "dex_test" if RUBY_PLATFORM.include?("android")
require_relative "java_test" if RUBY_PLATFORM.include?("android")
require_relative "objc_test" if RUBY_PLATFORM.include?("darwin")
require_relative "screen_test"
