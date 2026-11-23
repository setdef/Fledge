#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Installs, in an Alpine 3.24 container, the packages each musl Linux job
# needs, pinned by version as the Ubuntu jobs pin theirs:
#
#   alpine-packages.sh build    what builds a musl runtime: a C toolchain,
#                               Rust for YJIT, Perl for OpenSSL's build,
#                               and binutils, whose objdump the license
#                               audit reads compiled files with
#   alpine-packages.sh apps     what a developer on Alpine builds apps
#                               with: git for Bundler, binutils' objdump,
#                               squashfs-tools' mksquashfs for an
#                               AppImage, and a C toolchain with
#                               pkg-config, which compile a gem with no
#                               build for the Ruby, as sqlite3 2.10.2 has
#                               none for 4.1, and linux-headers, the
#                               kernel's headers, which build-base leaves
#                               out and the libffi ffi 1.17.4 carries
#                               includes, as doc/gems.md tells a
#                               developer on Alpine
#   alpine-packages.sh deliver  what Delivery checks a built app with, on
#                               a computer with no Ruby: script(1) and
#                               pgrep for the console,
#                               desktop-file-validate; file, which
#                               reads an icon's size; and curl, which
#                               asks a server app as a browser would
#   alpine-packages.sh parity   what the parity check needs beyond apps:
#                               GLib's gio, which launches a windowed
#                               app's desktop entry as a desktop does
#
# Each package's version is pinned in runtime/sources.yml, under
# alpine-packages, beside this script's checkout, where the pin move can
# rewrite it. An Alpine branch keeps only each package's newest build, so
# a pin that stops resolving fails the job until the pin watch moves it
# (doc/contributors/design/runtimes.md, "Alpine's packages"). The
# versions are read with awk, since Delivery's Alpine has no Ruby.

set -eu

case "${1:?usage: alpine-packages.sh build|apps|deliver|parity}" in
  build) names="build-base gcc musl-dev make linux-headers rust cargo perl binutils file tar xz zstd" ;;
  apps) names="git binutils tar squashfs-tools build-base gcc musl-dev make linux-headers pkgconf" ;;
  deliver) names="util-linux-misc procps-ng desktop-file-utils file curl" ;;
  parity) names="glib" ;;
  *)
    echo "alpine-packages.sh: unknown role $1" >&2
    exit 2
    ;;
esac
sources="$(dirname "$0")/../../runtime/sources.yml"
set --
for name in $names; do
  version=$(awk -v name="$name:" '
    /^[^ #]/ { inside = ($0 == "alpine-packages:") }
    inside && $1 == name { print $2; exit }' "$sources")
  if [ -z "$version" ]; then
    echo "alpine-packages.sh: $sources pins no version of $name under alpine-packages" >&2
    exit 2
  fi
  set -- "$@" "$name=$version"
done
apk add --no-cache "$@"
