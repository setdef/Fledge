# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# The app that proves a Rakefile's extensions on iOS, iPadOS, and
# Android: digest-crc, whose Rakefile builds a C extension for each CRC.
# digest-crc falls back to Ruby when an extension does not load, so the
# line says which ran: its C extension defines Digest::CRC32#update,
# which then has no Ruby source.
require "digest/crc32"

language = Digest::CRC32.instance_method(:update).source_location ? "Ruby" : "C"
puts "RakePhone: CRC32 of hello is #{Digest::CRC32.hexdigest('hello')} in #{language}, " \
  "from digest-crc #{Gem.loaded_specs.fetch('digest-crc').version}'s Rakefile, on #{RUBY_PLATFORM}"
