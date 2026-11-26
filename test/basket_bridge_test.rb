# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Basket's bridge to the Objective-C runtime
# (examples/basket/lib/basket/objc.rb), whose tests are Basket's, in
# examples/basket/test/objc_test.rb, where a developer reads them and
# runs them with ruby; this runs them in Fledge's unit tests, on a Mac,
# whose libobjc and Foundation are the runtime and classes an iPhone has.
# The part of Basket's calls into Java that needs no Java
# (examples/basket/lib/basket/android/member.rb) runs here too.
require_relative "test_helper"
require_relative "../examples/basket/test/objc_test"
require_relative "../examples/basket/test/java_test"
