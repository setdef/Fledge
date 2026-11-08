#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# A Linux build takes the icon sizes a project has (Plan 003, "A Linux
# build takes the icon sizes a developer has"; ADR 010, section 4):
# examples/windowed_app with only its 32-, 128-, and 256-pixel PNGs, as
# other bundlers' icon tools make a set, builds, names the three sizes it
# lacks on standard error, and its .deb and AppImage hold three hicolor
# icons, the AppImage's top one the 256-pixel PNG, with a desktop entry
# desktop-file-validate accepts; with no PNG at all it fails, naming the
# smallest.
#
#   check-icon-sizes.sh WORK
#
# Run from Fledge's checkout on a glibc Linux computer with dpkg-deb,
# mksquashfs, and desktop-file-validate, with FLEDGE_RUNTIME_DIR naming
# the runtime. WORK is an empty folder for the project and its builds.

set -eu

work=$1
project="$work/project"
dist="$work/dist"
platform=$(ruby -I lib -e 'require "fledge/platform"; print Fledge::Platform.local')
identifier=com.setdef.fledge.HelloWindow

fail() {
  echo "::error::icon sizes: $*" >&2
  exit 1
}

cp -R examples/windowed_app "$project"
rm "$project"/icons/icon-16.png "$project"/icons/icon-64.png "$project"/icons/icon-512.png
ruby -I lib exe/fledge build -o "$dist" "$project" 2>"$work/err" || { cat "$work/err"; fail "the build failed"; }
cat "$work/err"
grep -qx "fledge build: warning: the icon has no icons/icon-16.png, icons/icon-64.png, icons/icon-512.png, so Linux desktops scale the nearest size there is" "$work/err" ||
  fail "the build did not name the three sizes it lacks"

expected="./usr/share/icons/hicolor/128x128/apps/$identifier.png
./usr/share/icons/hicolor/256x256/apps/$identifier.png
./usr/share/icons/hicolor/32x32/apps/$identifier.png"
deb="$dist/Hello Window-$platform.deb"
icons=$(dpkg-deb -c "$deb" | awk '{ print $6 }' | grep '^\./usr/share/icons/.*\.png$' | sort)
[ "$icons" = "$expected" ] || fail "the .deb holds the icons $icons"
echo "ok: the .deb holds three hicolor icons"
dpkg-deb -x "$deb" "$work/deb"
desktop-file-validate "$work/deb/usr/share/applications/$identifier.desktop" || fail "desktop-file-validate rejects the .deb's desktop entry"
echo "ok: desktop-file-validate accepts the .deb's desktop entry"

(cd "$work" && "$dist/Hello Window-$platform.AppImage" --appimage-extract >/dev/null) || fail "the AppImage would not extract itself"
icons=$(cd "$work/squashfs-root" && find share/icons -name '*.png' | sed 's|^|./usr/|' | sort)
[ "$icons" = "$expected" ] || fail "the AppImage holds the icons $icons"
cmp -s "$work/squashfs-root/$identifier.png" "$project/icons/icon-256.png" || fail "the AppImage's top icon is not the 256-pixel PNG"
desktop-file-validate "$work/squashfs-root/$identifier.desktop" || fail "desktop-file-validate rejects the AppImage's desktop entry"
echo "ok: the AppImage holds three hicolor icons, the 256-pixel one at its top"

rm "$project"/icons/icon-*.png
status=0
ruby -I lib exe/fledge build -o "$work/none" "$project" 2>"$work/err" || status=$?
cat "$work/err"
[ "$status" = 1 ] || fail "the build with no PNG exited with $status, not 1"
grep -q "fledge build: the icon icons/icon-16.png does not exist" "$work/err" || fail "the build with no PNG did not name icons/icon-16.png"
echo "ok: a project with no PNG fails, naming the smallest"
