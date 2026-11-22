# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "mkmf"

# MSYS2's libz.dll.a, which GNU ld takes before libz.a, so the
# extension imports libz-1.dll.
abort "no zlib to link against" unless have_library("z", "crc32", "zlib.h")
create_makefile "linked_zlib"
