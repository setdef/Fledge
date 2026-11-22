# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "mkmf"
require "rb_sys/mkmf"

create_rust_makefile("lengths/lengths") do |config|
  config.extra_cargo_args += ["--locked"]
end
