#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# The LibUI probe, built: unpacks what fledge build wrote for
# test/fixtures/libui, starts its program from / with no Ruby on its
# PATH, and reads the report it writes once its window has been shown
# for a second: the window must have been visible, with its title, and
# LibUI must have opened its own gem's library.
#
#   deliver-libui.sh ARCHIVE LIBRARY [without-gtk]
#
# ARCHIVE is "LibUIProbe-PLATFORM.tar.gz", or ".zip" on Windows; LIBRARY
# is the file of libui-ng's library LibUI opens there, such as
# libui.arm64.dylib. On macOS the app runs through its own program,
# through open -W, as Finder starts it, and through open -a with a
# document, as a double-click on one starts it. On Linux it runs on the display
# DISPLAY names, or on an Xvfb of its own when none is named, with the
# distribution's GTK 3; with without-gtk, on a computer that has no GTK
# 3 yet, its program must instead name a library it lacks and exit with
# 72, naming no gem, as fledge.yml's linux: system_libraries makes it. On
# Windows the app must carry the three DLLs of Microsoft's Visual C++ runtime
# that its fledge.yml asks for, in ruby\bin\ruby_builtin_dlls; it runs with
# System32 alone on its PATH, since Windows needs some of its environment to
# start a program. A run that has not ended after 90 seconds fails.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1
library=$2

fail() {
  echo "::error::Delivery (LibUI): $*" >&2
  exit 1
}

work=$(mktemp -d)
cleanup() {
  [ -z "${xvfb:-}" ] || kill "$xvfb" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
os=$(uname -s)
case $os in MINGW* | MSYS*) os=Windows ;; esac

# native PATH: the path as the app's own program reads it.
native() {
  if [ "$os" = Windows ]; then cygpath -w "$1"; else printf '%s\n' "$1"; fi
}

# limit COMMAND...: runs COMMAND, ends it after 90 seconds, and returns
# its status. macOS has no timeout(1).
limit() {
  "$@" &
  pid=$!
  (sleep 90 && kill "$pid" 2>/dev/null) &
  watcher=$!
  status=0
  wait "$pid" || status=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  return "$status"
}

# check REPORT LABEL
check() {
  [ -s "$1" ] || fail "$2 wrote no report"
  for fact in '"ruby":"4.1.0"' "\"library\":\"$library\"" '"title":"Hello LibUI"' '"visible":true'; do
    grep -q "$fact" "$1" || fail "$2's report lacks $fact: $(cat "$1")"
  done
  echo "ok: $2 showed its window and reported $(cat "$1")"
}

place="$work/My Apps"
mkdir -p "$place" "$work/empty-path"
case $archive in
  # Windows' own tar, which is libarchive's and reads a .zip.
  *.zip) "$(cygpath -u "$SYSTEMROOT")/System32/tar.exe" -xf "$(native "$archive")" -C "$(native "$place")" ;;
  *) tar -xzf "$archive" -C "$place" ;;
esac

case $os in
  Darwin)
    bundle=$(find "$place" -maxdepth 2 -name 'LibUIProbe.app' | head -n 1)
    program="$bundle/Contents/MacOS/LibUIProbe"
    ;;
  Windows) program=$(find "$place" -maxdepth 2 -name 'LibUIProbe.exe' | head -n 1) ;;
  *) program=$(find "$place" -maxdepth 2 -type f -name 'LibUIProbe' | head -n 1) ;;
esac
[ -n "$program" ] && [ -f "$program" ] || fail "no program of LibUIProbe in $(basename "$archive")"
found=$(find "$place" -name "$library" | head -n 1)
[ -n "$found" ] || fail "the app holds no $library"
echo "ok: the app holds ${found#"$place/"}"

if [ "$os" = Windows ]; then
  builtin=$(dirname "$program")/ruby/bin/ruby_builtin_dlls
  for dll in vcruntime140.dll vcruntime140_1.dll msvcp140.dll; do
    [ -n "$(find "$builtin" -maxdepth 1 -iname "$dll")" ] || fail "the app does not carry $dll in ruby/bin/ruby_builtin_dlls"
    echo "ok: the app carries $dll"
  done
  (cd / && limit env PATH="$(cygpath -u "$SYSTEMROOT")/System32" "$program" "$(native "$work/program.json")") ||
    fail "its program exited with $?"
elif [ "${3:-}" = without-gtk ]; then
  if ls /usr/lib/*/libgtk-3.so.0 >/dev/null 2>&1; then
    fail "this computer has GTK 3 before the test begins"
  fi
  status=0
  out=$(cd / && env -i PATH="$work/empty-path" HOME="$work" "$program" "$work/program.json" 2>&1) || status=$?
  echo "without GTK 3: $out"
  [ "$status" -eq 72 ] || fail "without GTK 3 its program exited with $status, not 72"
  # The launcher begins its message with the program's own name, which
  # holds the gem's ("LibUIProbe: this app needs ..."), so only what
  # follows that name may not name Ruby or the gem.
  message=${out#LibUIProbe: }
  [ "$message" != "$out" ] || fail "without GTK 3 its program's message does not begin with its own name"
  printf '%s' "$message" | grep -Eq "^this app needs lib[a-z0-9.-]+\.so\.[0-9]+, which this computer does not have" ||
    fail "without GTK 3 its program did not name the library it lacks"
  if printf '%s' "$message" | grep -qi "ruby\|libui\|LoadError\|gem"; then
    fail "without GTK 3 its program named Ruby or a gem"
  fi
  echo "ok: without GTK 3 its program names a library it lacks and exits with 72"
  exit 0
else
  if [ "$os" = Linux ] && [ -z "${DISPLAY:-}" ]; then
    Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp >"$work/xvfb.log" 2>&1 &
    xvfb=$!
    sleep 3
    kill -0 "$xvfb" 2>/dev/null || fail "Xvfb did not start: $(cat "$work/xvfb.log")"
    DISPLAY=:99
  fi
  if env -i PATH="$work/empty-path" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
    fail "ruby is still reachable on the app's PATH"
  fi
  (cd / && limit env -i PATH="$work/empty-path" HOME="$work" ${DISPLAY:+DISPLAY="$DISPLAY"} "$program" "$work/program.json") ||
    fail "its program exited with $?"
fi
check "$work/program.json" "its own program"

if [ "$os" = Darwin ]; then
  limit open -n -W "$bundle" --args "$work/open.json" || fail "open -W exited with $?"
  check "$work/open.json" "open -W"
  # Opened with a document, as a double-click on one in Finder opens it:
  # the launcher takes the Open Documents Apple event before Ruby starts
  # and gives the program the document's path, over which the probe
  # writes its report, and LibUI must still show its window.
  document="$work/Geöffnet.libuiprobe"
  : >"$document"
  limit open -n -W -a "$bundle" "$document" || fail "open -a with a document exited with $?"
  check "$document" "open -a with a document"
fi
