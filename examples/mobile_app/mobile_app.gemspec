# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "lib/mobile_app/version"

# A gem-shaped app whose gems are all pure Ruby, laid out as bundle gem
# lays one out, which Fledge ships to every desktop and, as an Xcode or
# Gradle project, to iOS and Android (ADR 012).
Gem::Specification.new do |spec|
  spec.name = "mobile_app"
  spec.version = MobileApp::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["me@kerricklong.com"]

  spec.summary = "Says hello through a chain of pure-Ruby gems, on a desktop or a phone."
  spec.homepage = "https://github.com/setdef/Fledge/tree/trunk/examples/mobile_app"
  spec.license = "MIT-0"
  spec.required_ruby_version = ">= 4.0.1"

  spec.files = Dir.glob("{exe,lib}/**/*", base: __dir__)
  spec.bindir = "exe"
  spec.executables = ["mobile_app"]
  spec.require_paths = ["lib"]

  # i18n is pure Ruby and depends on concurrent-ruby, pure Ruby too.
  spec.add_dependency "i18n", "~> 1.15"
end
