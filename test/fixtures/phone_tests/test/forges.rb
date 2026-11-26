# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# A program that prints the line the host logs when a program ends, with
# status 0, runs on long enough for fledge test to read it, then ends with
# status 1. Only the exit status, as under ruby, may decide the result.
$stdout.sync = true
puts "PhoneTests exited with status 0"
sleep 6
puts "PhoneTests ended after its forged line"
exit 1
