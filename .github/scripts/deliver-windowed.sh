#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of a windowed app (ADR 008) on macOS and Linux: unpacks what
# fledge build wrote for examples/windowed_app, checks the identity each
# operating system reads with that system's own tools, and starts the
# app the way the system would, with no Ruby anywhere it can reach.
#
#   deliver-windowed.sh ARCHIVE
#
# ARCHIVE is "Hello Window-PLATFORM.tar.gz". On macOS the app is an .app
# bundle: codesign must verify it strictly and deeply, plutil must read
# what fledge.yml says from its Info.plist, and it must run both through
# open -W, as Finder starts it, and through its own program. On Linux it
# is a folder with a desktop entry, which desktop-file-validate must
# accept, and icons in the hicolor theme's folders. The app writes a
# report of what it ran on to the path it is given, and exits with the
# status it is given.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1
name="Hello Window"
identifier=com.setdef.fledge.HelloWindow
version=1.2.3

fail() {
  echo "::error::Delivery (windowed): $*" >&2
  exit 1
}

# expect LABEL ACTUAL EXPECTED
expect() {
  [ "$2" = "$3" ] || fail "$1 is '$2', not '$3'"
  echo "ok: $1 is $3"
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
archive=$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")
folder=$(basename "$archive" .tar.gz)
place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place"
tar -xzf "$archive" -C "$place"
root="$place/$folder"

empty="$work/empty-path"
mkdir -p "$empty"
if env -i PATH="$empty" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi

# run_report LABEL STATUS PROGRAM: runs PROGRAM from / in an empty
# environment, and fails unless it exits with STATUS and its report says
# it ran this runtime's Ruby, from the app's own folder.
run_report() {
  report="$work/report-$1.json"
  set +e
  (cd / && env -i PATH="$empty" HOME="$work" "$3" "$report" "$2") >"$work/out" 2>"$work/err"
  actual=$?
  set -e
  [ "$actual" -eq "$2" ] || { cat "$work/out" "$work/err"; fail "$1: exit status $actual, not $2"; }
  [ ! -s "$work/err" ] || { cat "$work/err"; fail "$1: it wrote to standard error"; }
  check_report "$1" "$report"
}

# check_report LABEL REPORT
check_report() {
  grep -q '"ruby":"4.0.9"' "$2" || fail "$1: the report says another Ruby: $(cat "$2")"
  grep -q '"program":"main.rb","folder":"app"' "$2" || fail "$1: the report says another program: $(cat "$2")"
  echo "ok: $1 ran and reported $(cat "$2")"
}

case "$(uname -s)" in
  Darwin)
    bundle="$root/$name.app"
    plist="$bundle/Contents/Info.plist"
    [ -d "$bundle" ] || fail "there is no $name.app in $folder"
    codesign --verify --strict --deep --verbose=2 "$bundle" || fail "codesign does not verify $name.app"
    codesign --display --verbose=2 "$bundle" 2>&1 | grep -qx "Identifier=$identifier" || fail "the signature does not name $identifier"
    echo "ok: codesign verifies $name.app, strictly and deeply, signed for $identifier"
    expect CFBundleIdentifier "$(plutil -extract CFBundleIdentifier raw "$plist")" "$identifier"
    expect CFBundleName "$(plutil -extract CFBundleName raw "$plist")" "$name"
    expect CFBundleDisplayName "$(plutil -extract CFBundleDisplayName raw "$plist")" "$name"
    expect CFBundleExecutable "$(plutil -extract CFBundleExecutable raw "$plist")" "$name"
    expect CFBundleShortVersionString "$(plutil -extract CFBundleShortVersionString raw "$plist")" "$version"
    expect CFBundleVersion "$(plutil -extract CFBundleVersion raw "$plist")" "$version"
    expect CFBundlePackageType "$(plutil -extract CFBundlePackageType raw "$plist")" APPL
    expect LSMinimumSystemVersion "$(plutil -extract LSMinimumSystemVersion raw "$plist")" 14.0
    expect NSHighResolutionCapable "$(plutil -extract NSHighResolutionCapable raw "$plist")" true
    expect NSHumanReadableCopyright "$(plutil -extract NSHumanReadableCopyright raw "$plist")" "© 2026 Kerrick Long"
    icon="$bundle/Contents/Resources/$(plutil -extract CFBundleIconFile raw "$plist")"
    expect "the icon's width" "$(sips -g pixelWidth "$icon" | sed -n 's/^ *pixelWidth: //p')" 1024
    grep -q "^This app was built with Fledge" "$bundle/Contents/Resources/notices/NOTICES.txt" || fail "the app has no notices"

    run_report "its own program" 4 "$bundle/Contents/MacOS/$name"
    # open -W starts the app as Finder does, through Launch Services, and
    # waits for it to quit; it does not pass the app's exit status on.
    report="$work/report-open.json"
    open -n -W "$bundle" --args "$report" 4 || fail "open could not start $name.app"
    check_report "open -W" "$report"
    ;;
  Linux)
    program="$root/$name"
    desktop="$root/$identifier.desktop"
    [ -x "$program" ] || fail "$name is not executable after unpacking"
    desktop-file-validate "$desktop" || fail "desktop-file-validate rejects $identifier.desktop"
    echo "ok: desktop-file-validate accepts $identifier.desktop"
    expect Name "$(sed -n 's/^Name=//p' "$desktop")" "$name"
    expect Exec "$(sed -n 's/^Exec=//p' "$desktop")" "\"$name\""
    expect Icon "$(sed -n 's/^Icon=//p' "$desktop")" "$identifier"
    expect Terminal "$(sed -n 's/^Terminal=//p' "$desktop")" false
    for size in 16 32 64 128 256 512; do
      icon="$root/share/icons/hicolor/${size}x$size/apps/$identifier.png"
      file "$icon" | grep -q "PNG image data, $size x $size" || fail "$icon is not a $size-pixel PNG: $(file "$icon")"
    done
    echo "ok: the hicolor theme's folders hold the icon at every size"
    grep -q "^This app was built with Fledge" "$root/notices/NOTICES.txt" || fail "the app has no notices"
    run_report "its program" 4 "$program"
    ;;
  *) fail "no windowed delivery for $(uname -s)" ;;
esac

echo "Delivered: $name, windowed"
