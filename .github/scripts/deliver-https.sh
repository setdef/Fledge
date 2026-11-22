#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
# Delivers the HTTPS probe (test/fixtures/https), built with fledge
# build: unpacks ARCHIVE in a folder of its own and runs the app with
# no Ruby of the computer's reachable, which asks rubygems.org over
# HTTPS and prints the status and the certificate file Ruby's OpenSSL
# was pointed at.
#
#   .github/scripts/deliver-https.sh ARCHIVE bundled|store [--remove-bundled]
#
# With bundled, the app must verify the server with the runtime's
# libexec/cert.pem, which SSL_CERT_FILE names, as on a glibc Linux with
# no certificate store of its own (a container with no
# ca-certificates). With store, the computer has a
# store, and a glibc Linux app must verify the server with it, no
# variable set (doc/contributors/design/runtimes.md, "Certificates on
# glibc Linux"). --remove-bundled deletes the runtime's libexec/cert.pem
# before the run, so that only the computer's store can serve; with
# bundled the check must then fail, which shows it fails when
# certificates do not work.

set -eu
archive=$1
expect=$2
remove=${3:-}

fail() {
  echo "::error::Delivery of the HTTPS probe: $*" >&2
  exit 1
}

case $expect in
  bundled | store) ;;
  *) fail "the second argument is bundled or store, not $expect" ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$archive" -C "$work"
folder=$(basename "$archive" .tar.gz)
root="$work/$folder"
app="$root/Https"
[ -x "$app" ] || fail "$app is not executable after unpacking"
bundled="$root/libexec/cert.pem"
[ -s "$bundled" ] || fail "the app carries no libexec/cert.pem"
if [ "$remove" = --remove-bundled ]; then
  rm "$bundled"
  echo "removed the runtime's libexec/cert.pem"
fi

empty="$work/empty-path"
mkdir -p "$empty"
status=0
(cd / && env -i PATH="$empty" HOME="$work" "$app") >"$work/out" 2>"$work/err" || status=$?
echo "--- stdout"; cat "$work/out"
echo "--- stderr"; cat "$work/err"
[ "$status" -eq 0 ] || fail "the app exited with $status"
line=$(cat "$work/out")
# The app's own file, by whichever path to its folder Ruby resolved.
case $expect in
  bundled) want="HTTPS to rubygems.org: 200, certificates SSL_CERT_FILE=.../$folder/libexec/cert.pem" ;;
  store) want="HTTPS to rubygems.org: 200, certificates from no file a variable names" ;;
esac
case $expect:$line in
  "bundled:HTTPS to rubygems.org: 200, certificates SSL_CERT_FILE=/"*"/$folder/libexec/cert.pem") ;;
  "store:$want") ;;
  *) fail "the app printed '$line', not '$want'" ;;
esac
echo "ok: $line"
