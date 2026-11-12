#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Prints the Ruby a job's ruby/setup-ruby installs: mise.toml's pin, the
# Ruby every other job and every contributor runs, since fledge build
# takes the runtime of the Ruby that runs it (ADR 055).
#
#   ruby-pin.sh
#
# On Windows, RubyInstaller publishes no build of a Ruby preview, so for
# a pin such as 4.1.0-preview1 it prints head: RubyInstaller's rolling
# build of Ruby's master, of the same minor, as setup-ruby installs it
# that day. The Windows runtimes are built from such a build too, pinned
# to one day's (runtime/sources.yml); the parity check compares an app
# with that pinned build, never with this one. head is not pinned, and
# goes when the pin is a release RubyInstaller builds.

set -eu

pin=$(sed -n 's/^ruby = { version = "\([^"]*\)".*/\1/p' mise.toml)
[ -n "$pin" ] || { echo "ruby-pin.sh: mise.toml pins no Ruby" >&2; exit 1; }

case "${RUNNER_OS:-}:$pin" in
  Windows:*-*) echo head ;;
  *) echo "$pin" ;;
esac
