# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# As Bundler's bundle gem --ext=c wrote it from Bundler 2.2.0 to 4.0.0:
# the extension by its path beside this file, where a desktop's RubyGems
# copies the file it compiles. On a phone the extension is linked into
# the app and registered under the name extconf.rb gave create_makefile
# (ADR 022), and fledge build puts a Ruby file at that path that requires
# it by that name, so this finds it there too.
require_relative "adder/adder"
