#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# In an Arch Linux container, which has no Ruby: builds the PKGBUILD from
# doc/package_managers.md with makepkg, as an AUR helper would, installs
# the package with pacman, runs hello by its command, and removes it.
#
#   deliver-aur.sh RECIPES RUBY_PLATFORM

set -eu

recipes=$1
platform=$2
here=$(cd "$(dirname "$0")" && pwd)

fail() {
  echo "::error::$*" >&2
  exit 1
}

if command -v ruby >/dev/null 2>&1; then
  fail "this container has Ruby at $(command -v ruby), so it cannot prove the app needs none"
fi

useradd -m builder
install -d -o builder /home/builder/hello
install -o builder "$recipes/aur/PKGBUILD" /home/builder/hello/PKGBUILD
su builder -c 'cd /home/builder/hello && makepkg --noconfirm'

pacman -U --noconfirm /home/builder/hello/hello-bin-*.pkg.tar.zst
HOME=/root "$here/package-manager-check.sh" /usr/bin "$platform"

pacman -R --noconfirm hello-bin
[ ! -e /usr/bin/hello ] || fail "removing left the command"
[ ! -e /opt/hello ] || fail "removing left the app"
