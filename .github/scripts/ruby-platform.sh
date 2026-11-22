#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Prints RUBY_PLATFORM as the runtime for PLATFORM, a Fledge target
# such as arm64-darwin, reports it: the arch runtime/licenses.yml's
# platforms give it, which the license audit holds every runtime build
# to. A macOS Ruby names its platform for the macOS it was built on
# (arm64-darwin23 on macOS 14), so a move of that Ruby's pin to a build
# made on a newer macOS changes the name there, which the move rewrites,
# and in no workflow, which the token that pushes a move cannot change
# (doc/contributors/design/runtimes.md, "The move").
#
#   .github/scripts/ruby-platform.sh arm64-darwin   # arm64-darwin23
set -euo pipefail

platform=$1
licenses="$(cd "$(dirname "$0")/../.." && pwd)/runtime/licenses.yml"
arch=$(awk -v name="$platform:" '$1 == name && match($0, /[{ ]arch: [^,}]*/) { print substr($0, RSTART + 7, RLENGTH - 7) }' "$licenses")
if [ -z "$arch" ]; then
  echo "runtime/licenses.yml gives no arch for the platform $platform" >&2
  exit 1
fi
echo "$arch"
