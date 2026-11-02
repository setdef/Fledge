# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# The app ADR 022's proof ships to iOS, iPadOS, and Android: a gem with a
# C and C++ extension, linked into the app and found by require. It
# prints one line, which the Mobile apps jobs read from the system log.
require "adder"

puts "NativePhone adds #{Adder.add(2, 3)} and totals #{Adder.total([1, 2, 3, 4])} with a C extension " \
  "(#{Adder.languages.join(' and ')}) on #{RUBY_PLATFORM}"
