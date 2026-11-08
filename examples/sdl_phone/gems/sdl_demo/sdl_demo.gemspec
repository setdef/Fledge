# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

Gem::Specification.new do |spec|
  spec.name = "sdl_demo"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A C extension that links SDL3 and runs a frame loop driven from Ruby, in examples/sdl_phone"
  spec.license = "MIT-0"
  spec.files = ["lib/sdl_demo.rb", "ext/sdl_demo/extconf.rb", "ext/sdl_demo/sdl_demo.c"]
  spec.extensions = ["ext/sdl_demo/extconf.rb"]
end
