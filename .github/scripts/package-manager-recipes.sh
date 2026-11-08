#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Writes each package manager's files from the code blocks of
# doc/package_managers.md, with the example release's address replaced by
# BASE_URL and each HASH FROM FILE by the hash in DIST/FILE, so that the
# recipes a developer reads are the ones CI installs. An archive this
# computer did not build gets a hash of zeros: its manager never reads it.
#
#   package-manager-recipes.sh DOC DIST BASE_URL OUT

set -eu

doc=$1
dist=$2
base=$3
out=$4

zeros=0000000000000000000000000000000000000000000000000000000000000000

# Prints the Nth fenced block under the "## SECTION" heading, without the
# carriage returns a Windows checkout adds.
block() {
  tr -d '\r' <"$doc" | awk -v section="## $1" -v want="$2" '
    /^## / { inside = ($0 == section); n = 0 }
    inside && /^```/ { fenced = !fenced; if (fenced) n++; next }
    inside && fenced && n == want { print }'
}

# Writes SECTION's Nth block to FILE, filled in.
recipe() {
  mkdir -p "$(dirname "$out/$3")"
  block "$1" "$2" | sed "s|https://github.com/example/hello/releases/download/v1.0.0|$base|g" >"$out/$3"
  [ -s "$out/$3" ] || {
    echo "::error::no block $2 under ## $1 in $doc" >&2
    exit 1
  }
  for name in $(grep -o "HASH FROM [^ \"']*" "$out/$3" | sed 's/HASH FROM //' | sort -u); do
    hash=$zeros
    [ ! -f "$dist/$name" ] || hash=$(cut -d' ' -f1 "$dist/$name" | tr -d '\r')
    sed "s/HASH FROM $name/$hash/g" "$out/$3" >"$out/$3.tmp"
    mv "$out/$3.tmp" "$out/$3"
  done
}

recipe Scoop 1 scoop/hello.json
recipe Homebrew 1 homebrew/hello.rb
recipe winget 1 winget/Example.Hello.yaml
recipe winget 2 winget/Example.Hello.locale.en-US.yaml
recipe winget 3 winget/Example.Hello.installer.yaml
recipe Chocolatey 1 chocolatey/hello.nuspec
recipe Chocolatey 2 chocolatey/tools/chocolateyInstall.ps1
recipe "The AUR" 1 aur/PKGBUILD
