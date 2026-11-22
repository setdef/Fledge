# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

Gem::Specification.new do |spec|
  spec.name = "echoer"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A gem whose extconf.rb builds a library for ffi, as sassc's does"
  spec.license = "MIT"
  spec.files = ["ext/echoer.cpp", "ext/extconf.rb", "lib/echoer.rb"]
  spec.extensions = ["ext/extconf.rb"]
  spec.required_ruby_version = ">= 3.2"
  spec.add_dependency "ffi", "~> 1.17"
end
