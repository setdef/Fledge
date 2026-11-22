# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Calls the C library through ffi, so its compiled ffi_c and the libffi
# linked into it must load and call out, and prints the same line under
# bundle exec and in the built app. Pass a number to exit with it, as
# Delivery's deliver.sh does to check that the status reaches the caller.
require "ffi"

module LibC
  extend FFI::Library

  ffi_lib FFI::Library::LIBC
  attach_function :strlen, [:string], :size_t
end

puts "ffi #{FFI::VERSION}: strlen(\"hello\") is #{LibC.strlen('hello')}"
exit Integer(ARGV.fetch(0, "0"))
