# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# rb-sys's Makefile, which runs Cargo, as a gem made with
# bundle gem --ext=rust has. --locked builds the crates Cargo.lock names,
# by the checksums it records.
require "mkmf"
require "rb_sys/mkmf"

create_rust_makefile("rusty/rusty") do |config|
  config.extra_cargo_args += ["--locked"]
end
