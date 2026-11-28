#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Copies each package manager's files from SRC, which holds one folder per
# manager, to OUT, with the example release's address replaced by
# BASE_URL and each HASH FROM FILE by the hash in DIST/FILE, so that CI
# installs the recipes a developer would write. An archive this computer
# did not build gets a hash of zeros: its manager never reads it.
#
#   package-manager-recipes.sh SRC DIST BASE_URL OUT

set -eu

src=$1
dist=$2
base=$3
out=$4

zeros=0000000000000000000000000000000000000000000000000000000000000000

# Copies the file at PATH under SRC to the same path under OUT, filled in,
# without the carriage returns a Windows checkout may add.
recipe() {
  mkdir -p "$(dirname "$out/$1")"
  tr -d '\r' <"$src/$1" | sed "s|https://github.com/example/hello/releases/download/v1.0.0|$base|g" >"$out/$1"
  [ -s "$out/$1" ] || {
    echo "::error::no recipe $1 in $src" >&2
    exit 1
  }
  grep -o "HASH FROM [^ \"']*" "$out/$1" | sed 's/HASH FROM //' | sort -u | while read -r name; do
    hash=$zeros
    [ ! -f "$dist/$name" ] || hash=$(cut -d' ' -f1 "$dist/$name" | tr -d '\r')
    sed "s/HASH FROM $name/$hash/g" "$out/$1" >"$out/$1.tmp"
    mv "$out/$1.tmp" "$out/$1"
  done
}

recipe scoop/hello.json
recipe homebrew/hello.rb
recipe winget/Example.Hello.yaml
recipe winget/Example.Hello.locale.en-US.yaml
recipe winget/Example.Hello.installer.yaml
recipe chocolatey/hello.nuspec
recipe chocolatey/tools/chocolateyInstall.ps1
recipe aur/PKGBUILD
