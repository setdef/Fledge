# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require "mkmf"

have_func("rb_str_new", "ruby.h")
create_makefile("adder/adder")
