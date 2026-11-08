# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

Gem::Specification.new do |spec|
  spec.name = "adder"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A gem with a C and C++ extension, in examples/native_phone"
  spec.license = "MIT-0"
  spec.files = ["lib/adder.rb", "ext/adder/extconf.rb", "ext/adder/adder.c", "ext/adder/total.cc", "ext/adder/total.h"]
  spec.extensions = ["ext/adder/extconf.rb"]
end
