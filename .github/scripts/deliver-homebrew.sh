#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Installs hello with Homebrew from a local tap, as doc/package_managers.md
# says, runs it by its command with no Ruby on PATH, and uninstalls it.
#
#   deliver-homebrew.sh RECIPES RUBY_PLATFORM

set -eu

recipes=$1
platform=$2
here=$(cd "$(dirname "$0")" && pwd)

export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ANALYTICS=1 NONINTERACTIVE=1

fail() {
  echo "::error::$*" >&2
  exit 1
}

[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ] || eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
if ! command -v brew >/dev/null 2>&1; then
  # Runners for arm64 Linux have no Homebrew. Its installer is pinned; the
  # Homebrew it installs is today's, as a person's is.
  installer=$(mktemp)
  curl -fsSL --retry 5 --retry-delay 5 -o "$installer" https://raw.githubusercontent.com/Homebrew/install/7986efac25016e41eed7e471666140c06f9d97cf/install.sh
  echo "5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148  $installer" | sha256sum -c
  bash "$installer"
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
brew --version

brew tap-new --no-git fledge-test/local
tap=$(brew --repository fledge-test/local)
mkdir -p "$tap/Formula"
cp "$recipes/homebrew/hello.rb" "$tap/Formula/hello.rb"

brew install --formula fledge-test/local/hello
brew test fledge-test/local/hello

prefix=$(brew --prefix)
links=$(find "$prefix/bin" -lname '*Cellar/hello/*' | wc -l | tr -d ' ')
[ "$links" = 1 ] || fail "Homebrew linked $links commands, not 1"

clean=$(mktemp -d)
ln -s "$prefix/bin/hello" "$clean/hello"
"$here/package-manager-check.sh" "$clean" "$platform"

brew uninstall --formula hello
[ ! -e "$prefix/bin/hello" ] || fail "uninstalling left the command"
[ ! -e "$(brew --cellar)/hello" ] || fail "uninstalling left the app"
