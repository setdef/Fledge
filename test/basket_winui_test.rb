# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Basket's screen on Windows with the Windows App Runtime
# (examples/basket/lib/basket/winui.rb), whose tests are Basket's, in
# examples/basket/test/winui_test.rb, where a developer reads them and
# runs them with ruby; this runs them in Fledge's unit tests, on Windows,
# and each skips, saying why, on a Windows without the Windows App
# Runtime and on the other systems.
require_relative "test_helper"
require_relative "../examples/basket/test/winui_test"
