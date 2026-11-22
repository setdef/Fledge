# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "mkmf"

# MSYS2's libffi.dll.a, as the ffi gem's extconf.rb takes it when it
# finds a libffi on the system, so the extension imports libffi-8.dll.
abort "no libffi to link against" unless have_library("ffi", "ffi_prep_cif", "ffi.h")
create_makefile "linked_ffi"
