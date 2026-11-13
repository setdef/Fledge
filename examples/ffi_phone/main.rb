# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# The app that proves the ffi gem on iOS, iPadOS, and Android: it calls
# the C library's strlen by name, and its qsort with a Ruby block as the
# comparison, a callback libffi makes at run time. iOS lets no app write
# code into memory and run it, so there libffi makes each callback from
# a page of trampolines compiled into the app.
require "ffi"

# The C library, through ffi.
module LibC
  extend FFI::Library

  ffi_lib FFI::Library::LIBC
  attach_function :strlen, [:string], :size_t
  callback :compare, %i[pointer pointer], :int
  attach_function :qsort, %i[pointer size_t size_t compare], :void
end

numbers = [3, 1, 2]
buffer = FFI::MemoryPointer.new(:int, numbers.size).write_array_of_int(numbers)
LibC.qsort(buffer, numbers.size, FFI.type_size(:int)) { |a, b| a.read_int <=> b.read_int }

puts "FfiPhone: ffi #{FFI::VERSION} finds strlen of hello #{LibC.strlen('hello')} and sorts " \
  "#{buffer.read_array_of_int(numbers.size).inspect} with a Ruby block, on #{RUBY_PLATFORM}"
