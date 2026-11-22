# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

Gem::Specification.new do |spec|
  spec.name = "greet"
  spec.version = "1.0.0"
  spec.authors = ["setdef"]
  spec.summary = "A path gem whose C extension links libgreet from the computer, in test/fixtures/carried_libraries"
  spec.license = "MIT"
  spec.files = ["lib/greet.rb", "ext/greet/extconf.rb", "ext/greet/greet.c"]
  spec.extensions = ["ext/greet/extconf.rb"]
end
