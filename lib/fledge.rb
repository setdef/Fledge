# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "fledge/version"
require_relative "fledge/error"
require_relative "fledge/platform"
require_relative "fledge/entry"
require_relative "fledge/command"
require_relative "fledge/archive"
require_relative "fledge/license_policy"
require_relative "fledge/icon"
require_relative "fledge/app"
require_relative "fledge/download"
require_relative "fledge/runtimes"
require_relative "fledge/assembly"
require_relative "fledge/cli"

# Ships a Ruby app to people who don't have Ruby.
#
# A Ruby app runs where Ruby is installed, and almost nobody who would
# use your game, desktop app, or terminal tool has Ruby installed. The
# Ruby on your own computer can't travel with the app: it was built for
# your machine, with your machine's paths and libraries baked in.
#
# Fledge copies your app into a runtime, a Ruby built to be moved plus
# a small launcher that runs the app on it, for each platform you ask
# for. The result runs where it lands.
#
# Use it from the command line, as <tt>fledge build</tt>; see
# Fledge::CLI.
#
# === Examples
#
#   # In a folder with a main.rb:
#   #   fledge build
#   # writes dist/NAME-PLATFORM/, which runs with no Ruby installed.
#
#   Fledge::VERSION # => "0.0.0"
module Fledge
end
