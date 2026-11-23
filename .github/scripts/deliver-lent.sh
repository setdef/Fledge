#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# examples/lent, built: unpacks what fledge build wrote for Lent, starts
# its program from / with no Ruby on its PATH and its data folder in a
# folder of the run's own, and reads the log Rails writes there: the web
# view in Lent's window must have asked for its first page, and Rails
# must have answered it, with no server. Then the database and the app's
# own secret must be in that data folder, nothing may have changed in the
# app's own folder, and no socket of the app's may be listening.
#
#   deliver-lent.sh ARCHIVE [without-libraries]
#
# ARCHIVE is "Lent-PLATFORM.tar.gz", or ".zip" on Windows. On macOS the
# data folder is HOME's Library/Application Support/Lent, on Windows
# APPDATA's Lent, and on Linux HOME's .local/share/lent; on Linux the app
# runs on the display DISPLAY names, or on an Xvfb of its own. With
# without-libraries, on a Linux that has no WebKitGTK yet, the program
# must instead name a library it lacks and exit with 72, naming no gem,
# as fledge.yml's linux: system_libraries makes it (doc/gems.md, "A gem
# that links a library from the Linux distribution"). An app that has not
# answered after 90 seconds fails.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1

fail() {
  echo "::error::Delivery (Lent): $*" >&2
  [ -z "${log:-}" ] || [ ! -f "$log" ] || { echo "--- the app's log:" >&2; cat "$log" >&2; }
  [ ! -f "${work:-}/app.out" ] || { echo "--- what the app printed:" >&2; cat "$work/app.out" >&2; }
  exit 1
}

work=$(mktemp -d)
cleanup() {
  [ -z "${pid:-}" ] || stop
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

place="$work/My Apps"
mkdir -p "$place" "$work/empty-path" "$work/home"
case $archive in
  # Windows' own tar, which is libarchive's and reads a .zip.
  *.zip) "$(cygpath -u "$SYSTEMROOT")/System32/tar.exe" -xf "$(native "$archive")" -C "$(native "$place")" ;;
  *) tar -xzf "$archive" -C "$place" ;;
esac

case $os in
  Darwin)
    program="$(find "$place" -maxdepth 2 -name Lent.app | head -n 1)/Contents/MacOS/Lent"
    data="$work/home/Library/Application Support/Lent"
    ;;
  Windows)
    program=$(find "$place" -maxdepth 2 -name Lent.exe | head -n 1)
    mkdir -p "$work/appdata"
    data="$work/appdata/Lent"
    ;;
  *)
    program=$(find "$place" -maxdepth 2 -type f -name Lent | head -n 1)
    data="$work/home/.local/share/lent"
    ;;
esac
[ -n "$program" ] && [ -f "$program" ] || fail "no program of Lent in $(basename "$archive"): $(cd "$place" && find . -maxdepth 2)"
log="$data/lent.log"

if [ "${2:-}" = without-libraries ]; then
  if ls /usr/lib/*/libwebkit2gtk-4.1.so.0 >/dev/null 2>&1; then
    fail "this computer has WebKitGTK before the test begins"
  fi
  status=0
  out=$(cd / && env -i PATH="$work/empty-path" HOME="$work/home" "$program" 2>&1) || status=$?
  echo "without WebKitGTK: $out"
  [ "$status" -eq 72 ] || fail "without WebKitGTK its program exited with $status, not 72"
  message=${out#Lent: }
  [ "$message" != "$out" ] || fail "without WebKitGTK its program's message does not begin with its own name"
  printf '%s' "$message" | grep -Eq "^this app needs lib[a-z0-9._-]+\.so\.[0-9]+, which this computer does not have" ||
    fail "without WebKitGTK its program did not name the library it lacks"
  if printf '%s' "$message" | grep -qi "ruby\|tokra\|LoadError\|gem"; then
    fail "without WebKitGTK its program named Ruby or a gem"
  fi
  [ ! -e "$data" ] || fail "without WebKitGTK its program made its data folder, so Ruby ran"
  echo "ok: without WebKitGTK its program names a library it lacks and exits with 72"
  exit 0
fi

if [ "$os" = Linux ] && [ -z "${DISPLAY:-}" ]; then
  Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp >"$work/xvfb.log" 2>&1 &
  xvfb=$!
  sleep 3
  kill -0 "$xvfb" 2>/dev/null || fail "Xvfb did not start: $(cat "$work/xvfb.log")"
  DISPLAY=:99
fi

# listening: the local addresses of every TCP socket listening on this
# computer, on Linux, which has no lsof or ss in a slim image. A socket
# that is listening once the app runs, and was not before, is the app's.
listening() {
  cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk 'NR > 1 && $4 == "0A" { print $2 }' | sort
}
[ "$os" != Linux ] || listening >"$work/listening-before"
(cd "$place" && find . | sort) >"$work/files-before"

# stop: ends the app this script started, and every process it started.
stop() {
  if [ "$os" = Windows ]; then
    [ -z "${winpid:-}" ] || taskkill //PID "$winpid" //T //F >/dev/null 2>&1 || true
  else
    kill "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
  pid=
}

if [ "$os" = Windows ]; then
  # Windows needs some of its environment to start a program.
  (cd / && exec env PATH="$(cygpath -u "$SYSTEMROOT")/System32" APPDATA="$(native "$work/appdata")" "$program") >"$work/app.out" 2>&1 &
  pid=$!
  sleep 1
  winpid=$(cat "/proc/$pid/winpid")
else
  (cd / && exec env -i PATH="$work/empty-path" HOME="$work/home" ${DISPLAY:+DISPLAY="$DISPLAY"} "$program") >"$work/app.out" 2>&1 &
  pid=$!
fi

waited=0
until [ -f "$log" ] && grep -q 'Started GET "/" for' "$log" && grep -q "Completed 200 OK" "$log"; do
  kill -0 "$pid" 2>/dev/null || fail "its program ended before Rails answered the window's first page"
  [ ! -f "$log" ] || ! grep -q "Completed [45][0-9][0-9]" "$log" || fail "Rails answered the window with an error"
  [ "$waited" -lt 90 ] || fail "Rails answered no first page for the window in 90 seconds"
  sleep 1
  waited=$((waited + 1))
done
echo "ok: the window asked for its first page, and Rails answered it, after $waited seconds"

for file in lent.sqlite3 secret_key_base; do
  [ -f "$data/$file" ] || fail "no $file in its data folder"
done
if [ "$os" != Windows ]; then
  [ -n "$(find "$data/secret_key_base" -perm 600)" ] || fail "its secret_key_base is readable by others than the person"
fi
echo "ok: its database and its secret are in its data folder: $(cd "$data" && echo *)"

case $os in
  Darwin) sockets=$(lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null || true) ;;
  Windows) sockets=$(netstat -ano | awk -v p="$winpid" '$1 == "TCP" && $4 == "LISTENING" && $5 == p') ;;
  *) sockets=$(listening | comm -13 "$work/listening-before" -) ;;
esac
[ -z "$sockets" ] || fail "it listens: $sockets"
echo "ok: it listens on no port"

stop
(cd "$place" && find . | sort) >"$work/files-after"
changed=$(diff "$work/files-before" "$work/files-after" || true)
[ -z "$changed" ] || fail "it changed its own folder: $changed"
echo "ok: it wrote nothing in its own folder"
cat "$log"
