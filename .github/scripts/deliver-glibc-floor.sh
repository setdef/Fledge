#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
# Delivers apps in IMAGE, a Linux whose glibc the runtimes' floor admits,
# with docker run, as a person who has no Ruby runs them there:
# hello and the floor-built my_cool_app by .github/scripts/deliver.sh
# --no-ruby-installed, and the HTTPS probe by
# .github/scripts/deliver-https.sh.
#
#   .github/scripts/deliver-glibc-floor.sh IMAGE PLATFORM DELIVERED FLOOR store|bundled
#
# store says the image has a certificate store, which must serve the
# probe, with the runtime's own file and without it; bundled says it has
# none, as Debian's and Ubuntu's images have no ca-certificates, so the
# runtime's file must serve, and without it the probe must fail, which
# shows the check fails when certificates do not work. Each PACKAGE is
# installed with dnf first: Amazon Linux 2023's image has no tar, which
# a person needs there to unpack any .tar.gz, and installs it so.
#
# DELIVERED holds the Build job's apps for PLATFORM (Hello, Parity,
# ParityBundle, Https, and my_cool_app.expected), and FLOOR the
# my_cool_app .github/scripts/glibc-app.sh built. The image runs from a
# step, not as the job's container, since GitHub's actions run inside a
# job's container and need what an image may lack.

set -eu
image=$1
platform=$2
delivered=$(cd "$3" && pwd)
floor=$(cd "$4" && pwd)
scripts=$(cd "$(dirname "$0")" && pwd)
case ${5:-} in
  store | bundled) certificates=$5 ;;
  *) echo "usage: deliver-glibc-floor.sh IMAGE PLATFORM DELIVERED FLOOR store|bundled [PACKAGE...]" >&2; exit 2 ;;
esac
shift 5
docker run --rm -v "$scripts:/s:ro" -v "$delivered:/d:ro" -v "$floor:/f:ro" \
  -e PLATFORM="$platform" -e EXPECTED="$(cat "$delivered/my_cool_app.expected")" -e CERTIFICATES="$certificates" \
  -e PACKAGES="$*" "$image" sh -c '
  set -eu
  [ -z "$PACKAGES" ] || dnf install -y -q $PACKAGES
  echo "glibc: $(ldd --version 2>&1 | sed -n 1p)"
  sh /s/deliver.sh "/d/Hello-$PLATFORM.tar.gz" "/d/Parity-$PLATFORM.tar.gz" "Hello from Ruby 4.1.0 on $PLATFORM" --no-ruby-installed
  sh /s/deliver.sh "/f/MyCoolApp-$PLATFORM.tar.gz" "/d/ParityBundle-$PLATFORM.tar.gz" "$EXPECTED" --no-ruby-installed
  sh /s/deliver-https.sh "/d/Https-$PLATFORM.tar.gz" "$CERTIFICATES"
  if [ "$CERTIFICATES" = store ]; then
    sh /s/deliver-https.sh "/d/Https-$PLATFORM.tar.gz" store --remove-bundled
  elif sh /s/deliver-https.sh "/d/Https-$PLATFORM.tar.gz" bundled --remove-bundled; then
    echo "::error::the HTTPS probe verified rubygems.org with no certificates at all" >&2
    exit 1
  else
    echo "ok: with no store and no bundled file, the HTTPS probe fails, as it must"
  fi'
