# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

Gem::Specification.new do |spec|
  spec.name = "shared"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A gem in a folder beside examples/real_gems, outside its project"
  spec.license = "MIT-0"
  spec.files = ["lib/shared.rb", "exe/shared-cli"]
  spec.bindir = "exe"
  spec.executables = ["shared-cli"]
end
