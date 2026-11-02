# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

Gem::Specification.new do |spec|
  spec.name = "greeter"
  spec.version = "1.0.0"
  spec.authors = ["Kerrick Long"]
  spec.summary = "A path gem with a C extension, in examples/real_gems"
  spec.license = "MIT-0"
  spec.files = ["lib/greeter.rb", "ext/greeter/extconf.rb", "ext/greeter/greeter.c"]
  spec.extensions = ["ext/greeter/extconf.rb"]
end
