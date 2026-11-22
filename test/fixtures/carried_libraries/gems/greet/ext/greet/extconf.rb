# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "mkmf"
unless have_header("greet.h") && have_library("greet", "greet_hello")
  abort "greet needs libgreet: put its folders on CPATH and LIBRARY_PATH, as test/integration/carried_libraries_test.rb does"
end
create_makefile("greet/greet")
