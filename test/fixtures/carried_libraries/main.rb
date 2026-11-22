# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Says what libgreet answers, through libpunct, on standard output, or in
# the file ARGV names, which a test reads when Finder's way of starting
# the app (open) leaves no standard output to read.
require "greet"

line = "greet: #{Greet.hello}\n"
ARGV.empty? ? $stdout.write(line) : File.write(ARGV.fetch(0), line)
