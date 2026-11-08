# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# The app ADR 027's proof ships to iOS, iPadOS, and Android: a gem whose
# extconf.rb builds a C++ library with CMake, linked into the app with
# the C extension over it. The library says which system CMake
# configured it for and which processor its compiler aimed at, so the
# line the Mobile apps jobs read from the system log shows that CMake
# cross-compiled it for the phone.
require "tally"

puts "CmakePhone totals #{Tally.sum([1, 2, 3, 4])} in C++ that #{Tally.built_for}, on #{RUBY_PLATFORM}"
