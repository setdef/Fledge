# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "lib/my_cool_app/version"

# test/fixtures/my_cool_app's gemspec without sqlite3, for the gem-shaped
# parity run on a platform where sqlite3 cannot be installed
# (Parity::WITHOUT_SQLITE3; doc/contributors/design/parity.md, "The
# gem-shaped run").
Gem::Specification.new do |spec|
  spec.name = "my_cool_app"
  spec.version = MyCoolApp::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["kerrick@setdef.com"]

  spec.summary = "Says hello through a pure-Ruby gem."
  spec.homepage = "https://github.com/setdef/Fledge/tree/trunk/test/fixtures/my_cool_app_without_sqlite3"
  spec.license = "MIT-0"
  spec.required_ruby_version = ">= 4.0.1"

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.bindir = "exe"
  spec.executables = ["my_cool_app"]
  spec.require_paths = ["lib"]

  # i18n is pure Ruby and depends on concurrent-ruby.
  spec.add_dependency "i18n", "~> 1.15"
end
