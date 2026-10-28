#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of a windowed app's AppImage (ADR 009) on Linux: the
# .AppImage fledge build wrote for examples/windowed_app, downloaded,
# made executable, and run as a person runs one, with no Ruby within its
# reach.
#
#   deliver-appimage.sh APPIMAGE fuse|extract
#
# APPIMAGE is "Hello Window-PLATFORM.AppImage". With fuse, the computer
# has FUSE, and the AppImage must mount itself and run from the mount,
# with the computer's fusermount, which AppImage's runtime finds on the
# PATH; with extract, it has none (a container), and the AppImage must
# say so, as AppImage's runtime does, and then extract itself and run
# from there when asked, with APPIMAGE_EXTRACT_AND_RUN=1 or
# --appimage-extract-and-run, as it also must anywhere. Either way,
# under a path with spaces and characters outside ASCII, with a PATH
# that holds no Ruby, and in a hostile Ruby environment, it must write
# its report and exit with the status it is given; and
# --appimage-extract must unpack an AppDir: AppRun linked to the app's
# program, the desktop entry and icon at the top, .DirIcon, and the
# app's notices.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

appimage=$1
mode=$2
name="Hello Window"
identifier=com.setdef.fledge.HelloWindow

fail() {
  echo "::error::Delivery (AppImage): $*" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place"
image="$place/$(basename "$appimage")"
cp "$appimage" "$image"
chmod +x "$image"

# A PATH with nothing on it but, where there is FUSE, its fusermount.
empty="$work/empty-path"
mkdir -p "$empty"
if [ "$mode" = fuse ]; then
  fusermount=$(command -v fusermount3 || command -v fusermount) || fail "this computer has FUSE but no fusermount"
  ln -s "$fusermount" "$empty/$(basename "$fusermount")"
fi
if env -i PATH="$empty" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi

evil="$work/evil"
mkdir -p "$evil/lib"
echo 'raise "Delivery: the user'"'"'s Ruby environment leaked into the app"' >"$evil/json.rb"
echo "not a library" >"$evil/lib/libcrypt.so.2"

# run LABEL WHERE [VAR=VALUE...]: runs the AppImage from / in an empty
# environment plus VAR=VALUE..., and fails unless it exits with 4,
# prints nothing on standard error, and reports this runtime's Ruby, run
# from a folder whose name begins with WHERE: .mount_ when mounted, or
# appimage_extracted_ when extracted.
run() {
  label=$1
  where=$2
  shift 2
  report="$work/report.json"
  rm -f "$report"
  set +e
  (cd / && env -i PATH="$empty" HOME="$work" TMPDIR="$work" "$@" "$image" "$report" 4) >"$work/out" 2>"$work/err"
  status=$?
  set -e
  [ "$status" -eq 4 ] || { cat "$work/out" "$work/err"; fail "$label: exit status $status, not 4"; }
  [ ! -s "$work/err" ] || { cat "$work/err"; fail "$label: it wrote to standard error"; }
  grep -q '"ruby":"4.0.9"' "$report" || fail "$label: the report says another Ruby: $(cat "$report")"
  grep -q '"program":"main.rb","folder":"app"' "$report" || fail "$label: the report says another program: $(cat "$report")"
  grep -q "\"appdir\":\"$where" "$report" || fail "$label: it did not run from a $where folder: $(cat "$report")"
  echo "ok: $label ran from $where..., and reported $(cat "$report")"
}

case "$mode" in
  fuse)
    run "its own way, mounted" .mount_
    hostile=""
    hostile_from=.mount_
    ;;
  extract)
    # With no FUSE, AppImage's runtime says what to do, and does not run.
    set +e
    (cd / && env -i PATH="$empty" HOME="$work" TMPDIR="$work" "$image" "$work/report.json" 4) >"$work/out" 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "with no FUSE, the AppImage ran without being asked to extract itself"
    grep -q "Cannot mount AppImage, please check your FUSE setup." "$work/out" || { cat "$work/out"; fail "with no FUSE, the AppImage did not say why"; }
    echo "ok: with no FUSE, the AppImage says to check FUSE, as AppImage's runtime does"
    hostile=APPIMAGE_EXTRACT_AND_RUN=1
    hostile_from=appimage_extracted_
    ;;
  *) fail "the mode is fuse or extract, not $mode" ;;
esac

run "APPIMAGE_EXTRACT_AND_RUN=1" appimage_extracted_ APPIMAGE_EXTRACT_AND_RUN=1
run "a hostile Ruby environment" "$hostile_from" $hostile RUBYLIB="$evil" RUBYOPT="-rjson" \
  GEM_HOME="$evil" GEM_PATH="$evil" BUNDLE_GEMFILE="$evil/Gemfile" LD_LIBRARY_PATH="$evil/lib"
# A mount goes away when the app's last process does, a moment after.
# (AppImage's runtime 20251108 leaves an extraction behind in TMPDIR: its
# rm_recursive passes nftw no file descriptors, which musl's nftw takes
# as nothing to do. That is AppImage's, and appimage_extracted_ folders
# are not checked here.)
tries=0
while leftover=$(find "$work" -maxdepth 1 -name '.mount_*' | head -n 1) && [ -n "$leftover" ]; do
  tries=$((tries + 1))
  [ "$tries" -lt 20 ] || fail "the AppImage left $leftover behind"
  sleep 0.5
done
echo "ok: the AppImage's mount went away"

(cd "$work" && "$image" --appimage-extract >/dev/null) || fail "--appimage-extract failed"
root="$work/squashfs-root"
[ "$(readlink "$root/AppRun")" = "$name" ] || fail "AppRun is not a link to $name"
[ -x "$root/$name" ] || fail "$name is not executable in the AppDir"
[ -f "$root/$identifier.desktop" ] || fail "the AppDir has no $identifier.desktop at its top"
[ -f "$root/$identifier.png" ] || fail "the AppDir has no $identifier.png at its top"
[ "$(readlink "$root/.DirIcon")" = "$identifier.png" ] || fail ".DirIcon is not a link to $identifier.png"
grep -q "^This app was built with Fledge" "$root/notices/NOTICES.txt" || fail "the AppDir has no notices"
grep -q "AppImage's type 2 runtime" "$root/notices/NOTICES.txt" || fail "the notices do not name the AppImage runtime"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$root/$identifier.desktop" || fail "desktop-file-validate rejects the AppDir's desktop entry"
  echo "ok: desktop-file-validate accepts the AppDir's desktop entry"
fi
echo "ok: --appimage-extract unpacks the AppDir"

echo "Delivered: $name, as an AppImage ($mode)"
