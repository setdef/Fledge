# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

Gem::Specification.new do |spec|
  spec.name = "rusty"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A Rust extension built with rb-sys and magnus, in examples/rust_phone"
  spec.license = "MIT-0"
  spec.files = [
    "lib/rusty.rb",
    "ext/rusty/extconf.rb",
    "ext/rusty/Cargo.toml",
    "ext/rusty/Cargo.lock",
    "ext/rusty/src/lib.rs",
  ]
  spec.extensions = ["ext/rusty/extconf.rb"]
  spec.add_dependency "rb_sys", "~> 0.9.130"
end
