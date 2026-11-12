# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# On a phone the extension is a static library linked into the app and
# registered under the name extconf.rb gave create_rust_makefile, so this
# require finds it without a file (ADR 022).
require "rusty/rusty"
