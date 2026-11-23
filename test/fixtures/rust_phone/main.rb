# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# The app that proves a Rust extension (rb-sys and magnus) runs on iOS,
# iPadOS, and Android: Cargo builds it for each of the phone's targets,
# and the app links it. It prints one line, which the Mobile apps jobs
# read from the system log, naming the system Rust compiled it for.
require "rusty"

puts "RustPhone totals #{Rusty.sum([1, 2, 3, 4])} in Rust built for #{Rusty.built_for}, on #{RUBY_PLATFORM}"
