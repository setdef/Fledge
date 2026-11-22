# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Whether a Rust extension's bindings declare rb_len_t, the type of
# lengths and indices in Ruby 4.1's C API, as the runtime's Ruby has it
# (doc/contributors/design/gems.md, "Rust gems on Windows and
# rb_len_t"). On every platform Fledge builds for it is 8 bytes. Bound
# as 4 where Ruby's is 8, rb_ary_entry reads the index -1 as 4294967295
# and finds nil, and rb_range_beg_len writes 8 bytes into each 4-byte
# slot, over the canary beside it.
require "lengths"

beginning, length, whole = Lengths.span(2..4, 10)
puts "RustLengths binds rb_len_t in #{Lengths.width} bytes, finds #{Lengths.last([1, 2, 3]).inspect} at -1 of [1, 2, 3], " \
  "and takes #{beginning} and #{length} of 10 for 2..4 with its canaries #{whole ? 'whole' : 'overwritten'}"
