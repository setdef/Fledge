#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
# Delivers apps in IMAGE, a Linux whose glibc the runtimes' floor admits,
# with docker run, as a person who has no Ruby runs them there:
# hello and the floor-built my_cool_app by .github/scripts/deliver.sh
# --no-ruby-installed, and the HTTPS probe by
# .github/scripts/deliver-https.sh, which asks a server this script runs
# on this computer (.github/scripts/https-server.sh) and the image
# reaches on this computer's network.
#
#   .github/scripts/deliver-glibc-floor.sh IMAGE PLATFORM DELIVERED FLOOR [PACKAGE...]
#
# Where the image has a certificate store, as AlmaLinux's and Amazon
# Linux's have, the probe must trust what the store holds and not the
# runtime's CA bundle; where it has none, as Debian's and Ubuntu's
# images have no ca-certificates, it must trust the bundle. The
# container is the check's own, so the store case changes the image's
# store (--store-may-change). Each PACKAGE is installed with dnf first:
# Amazon Linux 2023's image has no tar, which a person needs there to
# unpack any .tar.gz, and installs it so.
#
# DELIVERED holds the Build job's apps for PLATFORM (Hello, Parity,
# ParityBundle, Https, and my_cool_app.expected), and FLOOR the
# my_cool_app .github/scripts/glibc-app.sh built. The image runs from a
# step, not as the job's container, since GitHub's actions run inside a
# job's container and need what an image may lack.
set -eu
[ $# -ge 4 ] || { echo "usage: deliver-glibc-floor.sh IMAGE PLATFORM DELIVERED FLOOR [PACKAGE...]" >&2; exit 2; }
image=$1
platform=$2
delivered=$(cd "$3" && pwd)
floor=$(cd "$4" && pwd)
scripts=$(cd "$(dirname "$0")" && pwd)
shift 4
server=$(mktemp -d)
trap '"$scripts/https-server.sh" stop "$server"; rm -rf "$server"' EXIT
"$scripts/https-server.sh" start "$server"
docker run --rm --network host -v "$scripts:/s:ro" -v "$delivered:/d:ro" -v "$floor:/f:ro" -v "$server:/https:ro" \
  -e PLATFORM="$platform" -e EXPECTED="$(cat "$delivered/my_cool_app.expected")" \
  -e PACKAGES="$*" "$image" sh -c '
  set -eu
  [ -z "$PACKAGES" ] || dnf install -y -q $PACKAGES
  echo "glibc: $(ldd --version 2>&1 | sed -n 1p)"
  sh /s/deliver.sh "/d/Hello-$PLATFORM.tar.gz" "/d/Parity-$PLATFORM.tar.gz" "Hello from Ruby 4.1.0 on $PLATFORM" --no-ruby-installed
  sh /s/deliver.sh "/f/MyCoolApp-$PLATFORM.tar.gz" "/d/ParityBundle-$PLATFORM.tar.gz" "$EXPECTED" --no-ruby-installed
  sh /s/deliver-https.sh "/d/Https-$PLATFORM.tar.gz" /https --store-may-change'
