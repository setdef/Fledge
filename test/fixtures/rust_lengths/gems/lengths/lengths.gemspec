# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

Gem::Specification.new do |spec|
  spec.name = "lengths"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A Rust extension on rb-sys alone that reports how its bindings declare rb_len_t"
  spec.license = "MIT-0"
  spec.files = [
    "lib/lengths.rb",
    "ext/lengths/extconf.rb",
    "ext/lengths/Cargo.toml",
    "ext/lengths/Cargo.lock",
    "ext/lengths/src/lib.rs",
  ]
  spec.extensions = ["ext/lengths/extconf.rb"]
  spec.add_dependency "rb_sys", "~> 0.9.130"
end
