#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of a windowed app's disk image (ADR 009) on macOS: the .dmg
# fledge build wrote for examples/windowed_app, opened and installed as
# a person does, with nothing of Fledge or Ruby within the app's reach.
#
#   deliver-dmg.sh DMG
#
# DMG is "Hello Window-arm64-darwin.dmg". hdiutil must verify its
# checksums and attach it, as a double-click does; the volume, named
# after the app, must hold the app's bundle, which codesign must verify
# strictly and deeply right there, and a link to /Applications. The app
# must run from the volume; then, dragged to an Applications folder (a
# copy, as Finder's drag makes one), its signature must still verify and
# it must run through open -W, as Finder starts it, and through its own
# program, with no Ruby on its PATH.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

dmg=$1
name="Hello Window"
identifier=com.setdef.fledge.HelloWindow

fail() {
  echo "::error::Delivery (dmg): $*" >&2
  exit 1
}

work=$(mktemp -d)
mount="$work/volume"
cleanup() {
  hdiutil detach -quiet "$mount" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

hdiutil verify "$dmg" || fail "hdiutil does not verify $dmg"
echo "ok: hdiutil verifies the image's checksums"
hdiutil imageinfo "$dmg" | grep -qx "Format: UDZO" || fail "$dmg is not a compressed (UDZO) image"
mkdir -p "$mount"
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$dmg" >/dev/null || fail "hdiutil cannot attach $dmg"
volume=$(diskutil info "$mount" | sed -n 's/^ *Volume Name: *//p')
[ "$volume" = "$name" ] || fail "the volume is named '$volume', not '$name'"
echo "ok: the volume is named $name"
[ "$(readlink "$mount/Applications")" = /Applications ] || fail "the image has no link to /Applications"
echo "ok: the image links to /Applications"
codesign --verify --strict --deep --verbose=2 "$mount/$name.app" || fail "codesign does not verify $name.app in the image"
echo "ok: codesign verifies $name.app in the image"

empty="$work/empty-path"
mkdir -p "$empty"
if env -i PATH="$empty" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi

# run_report LABEL PROGRAM: runs PROGRAM from / in an empty environment,
# and fails unless it exits with 4 and reports this runtime's Ruby.
run_report() {
  report="$work/report-$1.json"
  set +e
  (cd / && env -i PATH="$empty" HOME="$work" "$2" "$report" 4) >"$work/out" 2>"$work/err"
  status=$?
  set -e
  [ "$status" -eq 4 ] || { cat "$work/out" "$work/err"; fail "$1: exit status $status, not 4"; }
  [ ! -s "$work/err" ] || { cat "$work/err"; fail "$1: it wrote to standard error"; }
  grep -q '"ruby":"4.0.9"' "$report" || fail "$1: the report says another Ruby: $(cat "$report")"
  echo "ok: $1 ran and reported $(cat "$report")"
}

run_report "the app in the image" "$mount/$name.app/Contents/MacOS/$name"

# The drag to Applications: Finder copies the bundle, links, modes, and
# all. A folder of this test's own stands in for /Applications.
applications="$work/Applications"
mkdir -p "$applications"
ditto "$mount/$name.app" "$applications/$name.app"
hdiutil detach -quiet "$mount"
codesign --verify --strict --deep --verbose=2 "$applications/$name.app" || fail "codesign does not verify the installed $name.app"
codesign --display --verbose=2 "$applications/$name.app" 2>&1 | grep -qx "Identifier=$identifier" || fail "the signature does not name $identifier"
echo "ok: codesign verifies the installed $name.app, signed for $identifier"
run_report "the installed app" "$applications/$name.app/Contents/MacOS/$name"
report="$work/report-open.json"
open -n -W "$applications/$name.app" --args "$report" 4 || fail "open could not start the installed $name.app"
grep -q '"ruby":"4.0.9"' "$report" || fail "open -W: no report from the installed app"
echo "ok: open -W started the installed app, which reported $(cat "$report")"

echo "Delivered: $name, from its disk image"
