# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Basket's screen on Windows (examples/basket/lib/basket/windows.rb),
# whose tests are Basket's, in examples/basket/test/windows_test.rb, where
# a developer reads them and runs them with ruby; this runs them in
# Fledge's unit tests, on Windows, whose user32 and comctl32 are the
# controls the screen is drawn with, and skips them on the other systems.
require_relative "test_helper"
require_relative "../examples/basket/test/windows_test"
