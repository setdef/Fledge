# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Downloads one input runtime/sources.yml pins, checked against its
# SHA-256, into tmp/downloads, and prints where it is.
#
#   ruby .github/scripts/fetch_pin.rb KEY...
#
# KEY... is the path to the pin in sources.yml, such as
# "ruby platforms x86_64-linux" or "replaceability musl".
require_relative "../../tasks/runtime_builder"

pin = RuntimeBuilder.new.sources.dig(*ARGV) or abort "no pin at #{ARGV.join(' ')} in runtime/sources.yml"
out = $stdout
$stdout = $stderr
out.puts RuntimeBuilder.new.fetch(pin.fetch("url"), pin.fetch("sha256"))
