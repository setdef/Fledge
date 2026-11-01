#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of a signed macOS build (ADR 016): examples/hello and
# examples/windowed_app, built with fledge build --sign and CI's test
# identity (make-test-identity.sh), checked on a fresh Mac with Apple's
# own codesign, and run.
#
#   deliver-signed.sh HELLO_ARCHIVE WINDOWED_ARCHIVE DISK_IMAGE CERTIFICATE
#
# The fresh Mac trusts CERTIFICATE for code signing first, as every Mac
# trusts Apple's Developer ID. Then every Mach-O program and library in
# both apps must verify strictly, carry the hardened runtime, a secure
# timestamp, and the identity's signature, and the programs Fledge's
# entitlements; the bundle must verify deeply as its identifier; the
# disk image must verify, and the bundle in it; both apps must run, the
# windowed one with YJIT writing machine code under the hardened
# runtime; and a file changed after signing must fail the bundle's
# verification. Nothing here may need Ruby.

set -eu

fail() {
  echo "::error::Delivery (signed): $*" >&2
  exit 1
}

work=$(mktemp -d)
trap 'hdiutil detach -quiet "$work/mount" 2>/dev/null || true; rm -rf "$work"' EXIT
authority="Authority=Fledge Test Signing"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$4"

mkdir -p "$work/apps"
tar -xzf "$1" -C "$work/apps"
tar -xzf "$2" -C "$work/apps"
hello="$work/apps/$(basename "$1" .tar.gz)"
bundle="$work/apps/$(basename "$2" .tar.gz)/Hello Window.app"

# check_code FOLDER: every Mach-O program and library under FOLDER (not
# object files, which nothing runs) verifies and is signed as it must be.
check_code() {
  count=0
  find "$1" -type f -print >"$work/files"
  while IFS= read -r file; do
    kind=$(file -b "$file")
    case "$kind" in
      *Mach-O*object*) continue ;;
      *Mach-O*) ;;
      *) continue ;;
    esac
    codesign --verify --strict "$file" 2>"$work/err" || { cat "$work/err"; fail "$file does not verify"; }
    codesign --display --verbose=2 "$file" >"$work/sig" 2>&1
    grep -q "flags=0x10000(runtime)" "$work/sig" || { cat "$work/sig"; fail "$file is not signed with the hardened runtime"; }
    grep -q "^Timestamp=" "$work/sig" || { cat "$work/sig"; fail "$file has no secure timestamp"; }
    grep -qF "$authority" "$work/sig" || { cat "$work/sig"; fail "$file is not signed by the test identity"; }
    count=$((count + 1))
  done <"$work/files"
  [ "$count" -gt 10 ] || fail "only $count Mach-O files in $1"
  echo "ok: $count Mach-O files in $(basename "$1") verify, with the hardened runtime, a timestamp, and the identity"
}

check_entitlements() {
  codesign --display --entitlements - --xml "$1" >"$work/entitlements" 2>/dev/null
  for key in com.apple.security.cs.allow-unsigned-executable-memory com.apple.security.cs.disable-library-validation; do
    grep -q "<key>$key</key>" "$work/entitlements" || { cat "$work/entitlements"; fail "$1 lacks $key"; }
  done
  echo "ok: $(basename "$1") carries Fledge's entitlements"
}

check_code "$hello"
check_entitlements "$hello/Hello"
out=$(cd / && env -i PATH=/usr/bin:/bin HOME="$work" "$hello/Hello")
case "$out" in "Hello from Ruby 4.0.9 on "*) echo "ok: Hello ran: $out" ;; *) fail "Hello printed: $out" ;; esac

check_code "$bundle/Contents/Resources"
codesign --verify --strict --deep --verbose=2 "$bundle" || fail "the bundle does not verify"
codesign --display --verbose=2 "$bundle" >"$work/sig" 2>&1
grep -q "^Identifier=com.setdef.fledge.HelloWindow$" "$work/sig" || { cat "$work/sig"; fail "the bundle is not signed as its identifier"; }
grep -q "flags=0x10000(runtime)" "$work/sig" || fail "the bundle is not signed with the hardened runtime"
grep -qF "$authority" "$work/sig" || fail "the bundle is not signed by the test identity"
check_entitlements "$bundle"
(cd / && env -i PATH=/usr/bin:/bin HOME="$work" "$bundle/Contents/MacOS/Hello Window" "$work/report.json" 0) ||
  fail "Hello Window did not run"
grep -q '"yjit":true' "$work/report.json" || fail "YJIT wrote no machine code under the hardened runtime: $(cat "$work/report.json")"
echo "ok: Hello Window ran, and YJIT wrote machine code: $(cat "$work/report.json")"

codesign --verify --strict --verbose=2 "$3" || fail "the disk image does not verify"
codesign --display --verbose=2 "$3" 2>&1 | grep -qF "$authority" || fail "the disk image is not signed by the test identity"
mkdir -p "$work/mount"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$work/mount" "$3"
codesign --verify --strict --deep "$work/mount/Hello Window.app" || fail "the bundle in the disk image does not verify"
hdiutil detach -quiet "$work/mount"
echo "ok: the disk image, and the bundle in it, verify"

echo "# changed after signing" >>"$bundle/Contents/Resources/app/main.rb"
if codesign --verify --strict --deep "$bundle" 2>/dev/null; then
  fail "the bundle still verifies after a file in it changed"
fi
echo "ok: a file changed after signing fails the bundle's verification"

echo "Delivered: the signed macOS apps"
