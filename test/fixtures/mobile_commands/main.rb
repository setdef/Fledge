# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# An Android app runs the command of a gem its Gemfile locks, thor, which
# no runtime has, by its name, as a program under bundle exec runs it:
# by name, from a shell, and with ruby -S, each a child Ruby with the
# app's bundle (doc/contributors/design/phone-runtimes.md, "Gem commands
# on Android"). tasks/mobile_parity.rb builds it with fledge build
# android, runs it on the emulator, and checks the line; iOS lets no app
# run a program.
require "rbconfig"

by_name = IO.popen(["thor", "version"], &:read).chomp
from_a_shell = `thor version 2>&1`.chomp
with_ruby_s = IO.popen([RbConfig.ruby, "-S", "thor", "version"], &:read).chomp
puts "MobileCommands runs thor by name (#{by_name}), from a shell (#{from_a_shell}), and with ruby -S (#{with_ruby_s}), " \
  "with Bundler's thor #{Gem.loaded_specs.fetch('thor').version}, on #{RUBY_PLATFORM}"
