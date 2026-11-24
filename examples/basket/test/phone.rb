# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Basket's tests inside the app on a phone: the list's, which also run
# on your own computer, and the screen's, which need the phone's own
# widgets. fledge test runs this file as the app's program, in place of
# main.rb, and exits with its status, as ruby test/phone.rb would:
#
#   fledge test ios test/phone.rb
#   fledge test android test/phone.rb

require_relative "list_test"
require_relative "screen_test"
