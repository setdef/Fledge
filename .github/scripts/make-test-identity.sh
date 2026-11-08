#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Makes a code signing identity for CI on macOS (ADR 016): a self-signed
# certificate, made fresh, with its key, in a temporary keychain that
# codesign searches, and trusted for code signing in the runner's system
# keychain, as a Developer ID is trusted on every Mac. No CI runner has
# an identity Apple issued; this proves the signing that does not need
# one.
#
#   make-test-identity.sh CERTIFICATE
#
# Writes the certificate, without its key, to CERTIFICATE, for Delivery
# to trust on a fresh runner, and FLEDGE_TEST_SIGN_IDENTITY, the name
# codesign finds it by, to $GITHUB_ENV.

set -eu

name="Fledge Test Signing"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
keychain="$RUNNER_TEMP/fledge-signing.keychain"
password=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=$name" \
  -keyout "$work/key.pem" -out "$work/certificate.pem" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/certificate.pem" -out "$work/identity.p12" -passout "pass:$password"

security create-keychain -p "$password" "$keychain"
security set-keychain-settings "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$work/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
# shellcheck disable=SC2046 # each keychain on the list is its own argument
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$work/certificate.pem"
security find-identity -v -p codesigning "$keychain" | grep -F "\"$name\""

cp "$work/certificate.pem" "$1"
echo "FLEDGE_TEST_SIGN_IDENTITY=$name" >>"$GITHUB_ENV"
