# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPIKE: Plan 001's hello app. json is a C extension, so a round trip
# proves extensions load from the runtime.
require "json"
raise "json round trip failed" unless JSON.parse(JSON.generate({ "a" => [1] })) == { "a" => [1] }

puts "Hello from Ruby #{RUBY_VERSION} on #{RUBY_PLATFORM}"
