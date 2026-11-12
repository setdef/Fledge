# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "mkmf"

# As digest-crc's do: once an extconf.rb writes extconf.h, mkmf puts
# $defs in the header and leaves them off the compile line.
have_header("stdint.h")
create_header
create_makefile "adler_ext"
