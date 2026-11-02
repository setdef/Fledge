# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# What fledge build delivers of the gems real apps lock (ADR 020). Each
# part comes from a different kind of gem; the last runs a gem's
# executable the way a program finds one, in Gem.bindir, with no Ruby on
# the PATH.
require "wisper"
require "shared"
require "greeter"
require "fledge_submodule_gem"
require "paint"

program = File.join(Gem.bindir, Gem.win_platform? ? "shared-cli.bat" : "shared-cli")
puts [
  "wisper #{Gem.loaded_specs.fetch('wisper').version} through a mirror that wanted a login",
  Shared.greeting,
  Greeter.greet,
  "fledge_submodule_gem says #{FledgeSubmoduleGem::README}",
  "paint #{Gem.loaded_specs.fetch('paint').version} from an optional group",
  IO.popen([program], &:read).strip,
].join("; ")
