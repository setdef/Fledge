# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# What fledge build delivers of the gems real apps lock
# (doc/contributors/design/gems.md, "Examples that exercise these
# rules"). Each
# part comes from a different kind of gem; the last runs a gem's
# executable the way a program finds one, in Gem.bindir, with no Ruby on
# the PATH.
require "wisper"
require "shared"
require "greeter"
require "fledge_submodule_gem"
require "paint"

# The program is a Ruby of its own, in this app's bundle. A person's own
# Ruby settings (RUBYOPT after Bundler's, RUBYLIB, BUNDLE_APP_CONFIG, and
# the rest) reach it, as under bundle exec (ADR 005), so Delivery's
# hostile ones, which name files that fail, are left out, keeping
# Bundler's -r...bundler/setup and the app's Gemfile.
program = File.join(Gem.bindir, Gem.win_platform? ? "shared-cli.bat" : "shared-cli")
settings = ENV.keys.grep(/\A(?:BUNDLE|BUNDLER|GEM|RUBY)/) - %w[BUNDLE_GEMFILE BUNDLE_LOCKFILE]
child = settings.to_h { |name| [name, nil] }
child["RUBYOPT"] = ENV.fetch("RUBYOPT", "")[%r{\A-r.*?bundler[\\/]setup}]
puts [
  "wisper #{Gem.loaded_specs.fetch('wisper').version} through a mirror that wanted a login",
  Shared.greeting,
  Greeter.greet,
  "fledge_submodule_gem says #{FledgeSubmoduleGem::README}",
  "paint #{Gem.loaded_specs.fetch('paint').version} from an optional group",
  IO.popen(child, [program], &:read).strip,
].join("; ")
exit Integer(ARGV.fetch(0, "0"))
