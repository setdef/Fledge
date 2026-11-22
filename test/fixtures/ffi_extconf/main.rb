# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Calls the library echoer's extconf.rb built, through Ruby's ffi, and
# says which file ffi opened it from.
require "echoer"

library = Echoer.ffi_libraries.first.name
puts "echoer: #{Echoer.shout('hello')} from #{library.split('/').last(3).join('/')}"
