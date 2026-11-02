# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++

# On a phone the extension is linked into the app and registered under
# the name extconf.rb gave create_makefile, so this require finds it
# without a file (ADR 022); on a desktop Bundler or RubyGems would have
# compiled it to a file beside this one.
require "adder/adder"
