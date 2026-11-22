#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
# Delivers the HTTPS probe (test/fixtures/https), built with fledge
# build, on macOS or Linux: unpacks ARCHIVE, Https-PLATFORM.tar.gz, in a
# folder of its own for each case and runs the app with no Ruby of the
# computer's reachable, asking the server .github/scripts/https-server.sh
# runs, whose FOLDER it is given. The server's certificate is signed by
# a test authority made for the run, FOLDER/ca.pem, and each case puts
# that certificate in one place and checks that the app trusts the
# server, or refuses it, as the platform's Ruby does under ruby main.rb
# (doc/contributors/design/runtimes.md, "Certificates"):
#
#   none      nowhere: every app refuses, so the check is seen to fail
#             when certificates do not work.
#   variable  in the file SSL_CERT_FILE names: every app trusts.
#   bundled   added to the runtime's CA bundle, libexec/cert.pem, in the
#             unpacked copy: trusted on macOS and musl Linux, and on
#             glibc Linux only where the computer has no store of its
#             own, since there the store is read in its place.
#   store     in the computer's own store: trusted on glibc Linux; on
#             musl Linux, under the hashed name in /etc/ssl/certs that
#             Alpine's update-ca-certificates gives it, which its Ruby's
#             OpenSSL looks up, and not from the bundle file there,
#             which it does not read; and refused on macOS, whose Ruby
#             does not read the Keychain.
#
#   .github/scripts/deliver-https.sh ARCHIVE FOLDER [--store-may-change]
#
# The store case changes the computer's trust, so it runs only on
# GitHub's runners (GITHUB_ACTIONS is true there; CI is set on other
# computers too) or where --store-may-change says the computer is a
# container made for the check, and on any other computer says it was
# not tried. On macOS it runs only on GitHub's runners, and leaves the
# authority in the System keychain, since taking it out again waited
# unanswered until the job's time ran out; each runner is a new machine,
# thrown away after its job.

set -eu
archive=$1
server=$2
may_change=${3:-}
[ -z "$may_change" ] || [ "$may_change" = --store-may-change ] || {
  echo "usage: deliver-https.sh ARCHIVE FOLDER [--store-may-change]" >&2
  exit 2
}

fail() {
  echo "::error::Delivery of the HTTPS probe: $*" >&2
  exit 1
}

[ -s "$server/ca.pem" ] && [ -s "$server/url" ] || fail "$server holds no ca.pem and url from https-server.sh"
url=$(cat "$server/url")
folder=$(basename "$archive" .tar.gz)
case $folder in
  *-darwin) system=macos ;;
  *-linux-musl) system=musl ;;
  *-linux) system=glibc ;;
  *) fail "$archive is not Https-PLATFORM.tar.gz for macOS or Linux" ;;
esac
# The computer's own store, as jdx/ruby's openssl.rb looks for it.
store=
for file in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
  if [ -s "$file" ]; then store=$file; break; fi
done

work=$(mktemp -d)
trusted=
cleanup() {
  [ -z "$trusted" ] || untrust
  rm -rf "$work"
}
trap cleanup EXIT

# Runs the app with the authority's certificate placed as $1 says and
# checks that it $2 (trusts or refuses) the server.
check() {
  run="$work/$1"
  mkdir -p "$run/empty-path"
  tar -xzf "$archive" -C "$run"
  root="$run/$folder"
  app="$root/Https"
  [ -x "$app" ] || fail "$app is not executable after unpacking"
  [ -s "$root/libexec/cert.pem" ] || fail "the app carries no libexec/cert.pem"
  set -- "$1" "$2" PATH="$run/empty-path" HOME="$run"
  case $1 in
    variable) set -- "$@" SSL_CERT_FILE="$server/ca.pem" ;;
    bundled) cat "$server/ca.pem" >>"$root/libexec/cert.pem" ;;
  esac
  name=$1 expect=$2
  shift 2
  status=0
  (cd / && env -i "$@" "$app" "$url") >"$run/out" 2>"$run/err" || status=$?
  line=$(cat "$run/out")
  case $expect:$status:$line in
    "trusts:0:HTTPS to 127.0.0.1: 200, certificates "*) ;;
    "refuses:1:HTTPS to 127.0.0.1: certificate verify failed"*) ;;
    *)
      echo "--- stdout"; cat "$run/out"
      echo "--- stderr"; cat "$run/err"
      fail "($name) on $system the app must say it $expect the server, but it exited with $status and printed '$line'"
      ;;
  esac
  echo "ok ($name, $expect): $line"
}

# Puts the authority in the computer's store, as a person or an
# administrator would, and untrust takes it out again, except on macOS.
trust() {
  case $system in
    macos) sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$server/ca.pem" ;;
    *)
      if [ -n "$may_change" ]; then
        [ -n "$store" ] || fail "--store-may-change, but this computer has no store"
        # AlmaLinux keeps its extracted bundle read-only, which only a
        # container's root may write past.
        chmod u+w "$store"
        cat "$server/ca.pem" >>"$store"
      else
        sudo cp "$server/ca.pem" /usr/local/share/ca-certificates/fledge-https-probe.crt
        sudo update-ca-certificates >/dev/null
      fi
      ;;
  esac
  trusted=yes
}
untrust() {
  trusted=
  case $system in
    macos)
      # Nothing: taking the authority out of the System keychain's
      # admin trust settings waited, unanswered, until the job's time
      # ran out, and the store case runs on macOS only on GitHub's
      # runners, each a new machine thrown away after its job.
      ;;
    *)
      [ -n "$may_change" ] || {
        sudo rm -f /usr/local/share/ca-certificates/fledge-https-probe.crt
        sudo update-ca-certificates --fresh >/dev/null
      }
      ;;
  esac
}

check none refuses
check variable trusts
case $system:$store in
  glibc:?*) check bundled refuses ;;
  *) check bundled trusts ;;
esac
if [ "${GITHUB_ACTIONS:-}" != true ] && [ -z "$may_change" ]; then
  echo "not tried (store): only on GitHub's runners or with --store-may-change, since it changes what this computer trusts"
elif [ "$system" = macos ] && [ "${GITHUB_ACTIONS:-}" != true ]; then
  echo "not tried (store): on macOS only on GitHub's runners, since the authority stays in the System keychain"
elif [ "$system" != macos ] && [ -z "$store" ]; then
  echo "not tried (store): this computer has no store"
else
  trust
  case $system in
    glibc) check store trusts ;;
    musl)
      # The bundle file the store holds is not what this Ruby reads;
      # the hashed name update-ca-certificates writes beside it is.
      check store refuses
      cp "$server/ca.pem" "/etc/ssl/certs/$(cat "$server/hash").0"
      check store trusts
      rm "/etc/ssl/certs/$(cat "$server/hash").0"
      ;;
    macos) check store refuses ;;
  esac
  untrust
fi
