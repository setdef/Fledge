#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Installs, in an Alpine 3.24 container, the packages each musl Linux job
# needs (ADR 017), pinned by version as the Ubuntu jobs pin theirs:
#
#   alpine-packages.sh build    what builds a musl runtime: a C toolchain,
#                               Rust for YJIT, Perl for OpenSSL's build,
#                               and binutils, whose objdump the license
#                               audit reads compiled files with
#   alpine-packages.sh apps     what a developer on Alpine builds apps
#                               with: git for Bundler, binutils' objdump,
#                               and squashfs-tools' mksquashfs for an
#                               AppImage
#   alpine-packages.sh deliver  what Delivery checks a built app with, on
#                               a computer with no Ruby: script(1) and
#                               pgrep for the console,
#                               desktop-file-validate, and file, which
#                               reads an icon's size
#
# An Alpine branch keeps only each package's newest build, so a pin that
# stops resolving fails the job, and is moved on purpose.

set -eu

case "${1:?usage: alpine-packages.sh build|apps|deliver}" in
  build)
    set -- build-base=0.5-r4 gcc=15.2.0-r5 musl-dev=1.2.6-r3 make=4.4.1-r4 linux-headers=7.0.0-r1 \
      rust=1.96.1-r0 cargo=1.96.1-r0 perl=5.42.2-r1 binutils=2.45.1-r1 file=5.47-r2 tar=1.35-r5 xz=5.8.4-r0 \
      zstd=1.5.7-r2
    ;;
  apps)
    set -- git=2.54.0-r0 binutils=2.45.1-r1 tar=1.35-r5 squashfs-tools=4.7.5-r0
    ;;
  deliver)
    set -- util-linux-misc=2.42.3-r1 procps-ng=4.0.6-r0 desktop-file-utils=0.28-r0 file=5.47-r2
    ;;
  *)
    echo "alpine-packages.sh: unknown role $1" >&2
    exit 2
    ;;
esac
apk add --no-cache "$@"
