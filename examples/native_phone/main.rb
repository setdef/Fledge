# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# The app CI ships to iOS, iPadOS, and Android to prove a gem's
# extension works there: a gem with a C and C++ extension, compiled for
# the phone and found by require
# (doc/contributors/design/phone-projects.md, "Gems with extensions").
# It prints one line, which the Mobile apps jobs read from the system
# log.
require "adder"

puts "NativePhone adds #{Adder.add(2, 3)} and totals #{Adder.total([1, 2, 3, 4])} with a C extension " \
  "(#{Adder.languages.join(' and ')}) on #{RUBY_PLATFORM}"
