# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Basket's bridge to GTK 4 and libadwaita (examples/basket/lib/basket/gtk.rb)
# and its screen on Linux, whose tests are Basket's, in
# examples/basket/test/gtk_test.rb, where a developer reads them and runs
# them with ruby; this runs them in Fledge's unit tests, and each skips,
# saying why, on a computer without fiddle (which Bundler hides until a
# Gemfile lists it), without GTK 4 and libadwaita, or without a display.
require_relative "test_helper"
require_relative "../examples/basket/test/gtk_test"
