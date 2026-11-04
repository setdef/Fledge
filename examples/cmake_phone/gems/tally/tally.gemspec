# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

Gem::Specification.new do |spec|
  spec.name = "tally"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A C extension over a C++ library that CMake builds, in examples/cmake_phone"
  spec.license = "MIT-0"
  spec.files = [
    "lib/tally.rb",
    "ext/tally/extconf.rb",
    "ext/tally/tally.c",
    "ext/tally/lib/CMakeLists.txt",
    "ext/tally/lib/tally.cc",
    "ext/tally/lib/tally.h",
  ]
  spec.extensions = ["ext/tally/extconf.rb"]
end
