# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

require_relative "lib/my_cool_app/version"

# A gem-shaped app, laid out as bundle gem lays one out, which Fledge
# ships as it is (ADR 005). Its files come from git, as bundle gem's
# template takes them; fledge build evaluates this file once, where git
# is, and ships the result, so the built app needs no git.
Gem::Specification.new do |spec|
  spec.name = "my_cool_app"
  spec.version = MyCoolApp::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["me@kerricklong.com"]

  spec.summary = "Says hello through a pure-Ruby gem and a native one."
  spec.homepage = "https://github.com/setdef/Fledge/tree/trunk/examples/my_cool_app"
  spec.license = "MIT-0"
  spec.required_ruby_version = ">= 4.0.1"

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.bindir = "exe"
  spec.executables = ["my_cool_app"]
  spec.require_paths = ["lib"]

  # i18n is pure Ruby and depends on concurrent-ruby; sqlite3 is native,
  # precompiled for every platform Fledge builds for.
  spec.add_dependency "i18n", "~> 1.15"
  spec.add_dependency "sqlite3", "~> 2.10"
end
