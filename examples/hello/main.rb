# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# The app Plan 001's walking skeleton ships: it greets you and exits.
#
# It prints one line, <tt>Hello from Ruby VERSION on PLATFORM</tt>,
# where PLATFORM is +RUBY_PLATFORM+: <tt>arm64-darwin23</tt> (rv-ruby
# builds for macOS 14, Darwin 23), <tt>x86_64-linux</tt>,
# <tt>aarch64-linux</tt>, or <tt>x64-mingw-ucrt</tt>. Delivery checks
# that line exactly.
#
# The line goes through JSON first. +json+ is a C extension in Ruby's
# standard library, so the line only prints when extensions load from
# the runtime; when they don't, the app fails instead.
#
# Pass a number to exit with it (<tt>hello 3</tt> exits with status 3),
# so Delivery can check that an app's exit status reaches whoever ran
# it.

require "json"

greeting = JSON.parse(JSON.generate({ "version" => RUBY_VERSION, "platform" => RUBY_PLATFORM }))
puts "Hello from Ruby #{greeting.fetch('version')} on #{greeting.fetch('platform')}"
exit Integer(ARGV.fetch(0, "0"))
