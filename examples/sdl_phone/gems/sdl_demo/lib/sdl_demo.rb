# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# On iOS the extension is linked into the app and registered under the
# name extconf.rb gave create_makefile, so this require finds it without
# a file (ADR 022). On Android it is a file, as on a desktop, which Ruby
# loads from where a desktop has it.
require "sdl_demo/sdl_demo"
