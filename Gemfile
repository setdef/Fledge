# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

source "https://rubygems.org"

# Specify your gem's dependencies in fledge.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 6.0"

gem "rubocop", "~> 1.21"
gem "rubocop-minitest", "~> 0.38"
gem "rubocop-rake", "~> 0.7"
gem "rubycritic", "~> 4.11"
gem "ostruct", "~> 0.6.3"
gem "inch", "~> 0.4"
gem "flog", "4.8.0"
gem "steep"
gem "rdoc", "~> 7.0"

# Checks lib/fledge/config.schema.json and the examples against it
# (doc/contributors/design/public-interface.md). Development only: nothing Fledge ships loads it.
gem "json_schemer", "~> 2.5", group: :development

# Takes the desktop input lock around local runs that can take focus or
# the pointer, such as a phone simulator (AGENTS.md, Commands). Pinned to
# a tag, and Gemfile.lock records its commit; nothing Fledge ships loads it.
gem "desktop_input_lock", git: "https://github.com/setdef/DesktopInputLock.git",
  tag: "v0.1.0", group: :development
