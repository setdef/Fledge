#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of a server (examples/file_drop, Drop, a file drop for the
# computers and phones on a network) on macOS or Linux: unpacks ARCHIVE,
# Drop-PLATFORM.tar.gz, makes the unpacked app read-only, as
# /Applications or an AppImage's mount leaves it, and runs it from / with
# no Ruby of the computer reachable, as a person starts it, and checks
# that:
#
#   - it prints the address other computers open, and a password;
#   - another process reaches it at that address, which is this
#     computer's own private IPv4 address, not loopback, wherever the
#     computer has one (where it has none, Drop prints localhost, and
#     the script says that it reached loopback only);
#   - it refuses a request without the password with 401;
#   - a file sent as its form sends it arrives in the Drop folder of the
#     person's home folder byte for byte, and a second client, as
#     another device would, finds it listed and fetches the same bytes;
#   - SIGINT, Ctrl-C's signal, stops it with status 0, and it printed
#     nothing on stderr.
#
# Each request goes to an address of this computer: none leaves it.
#
#   deliver-server.sh ARCHIVE
#   deliver-server.sh --reference COMMAND...
#
# With --reference, it runs COMMAND, such as bundle exec ruby main.rb in
# the example's folder, in place of the app, with no read-only folder,
# and expects exactly the same; the integration test runs both. It asks
# with curl, as a browser would. PORT sets another port than 4567,
# Sinatra's.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

fail() {
  echo "::error::Delivery (server): $*" >&2
  exit 1
}

port=${PORT:-4567}
work=$(mktemp -d)
pid=
cleanup() {
  [ -z "$pid" ] || kill -KILL "$pid" 2>/dev/null || true
  chmod -R u+w "$work" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
home="$work/home"
mkdir -p "$home" "$work/empty-path"

if [ "$1" = "--reference" ]; then
  shift
  set -- env HOME="$home" "$@"
  label="the reference"
else
  archive=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  folder=$(basename "$archive" .tar.gz)
  mkdir -p "$work/apps"
  tar -xzf "$archive" -C "$work/apps"
  app="$work/apps/$folder/Drop"
  [ -x "$app" ] || fail "$app is not executable after unpacking"
  chmod -R a-w "$work/apps"
  set -- env -i PATH="$work/empty-path" HOME="$home" "$app"
  label="the built app"
fi

show() {
  echo "--- stdout"; cat "$work/out"; echo "--- stderr"; cat "$work/err"
}

# request NAME URL [CURL OPTION...]: asks URL with curl, into
# $work/NAME, and prints the status of the response, 000 if none came.
request() {
  into="$work/$1" address=$2
  shift 2
  curl -s -o "$into" -w '%{http_code}' "$@" "$address" || true
}

(cd / && exec "$@" -p "$port") >"$work/out" 2>"$work/err" &
pid=$!
tries=0
until grep -q '^Press Ctrl-C to stop\.$' "$work/out" 2>/dev/null; do
  kill -0 "$pid" 2>/dev/null || { show; fail "$label ended before it printed its address"; }
  tries=$((tries + 1))
  [ "$tries" -lt 120 ] || { show; fail "$label did not print its address within 30 seconds"; }
  sleep 0.25
done
[ "$(sed -n 1p "$work/out")" = "Drop is sharing $home/Drop" ] || { show; fail "$label does not share the Drop folder of the person's home folder"; }
url=$(sed -n 's|^  \(http://[^ ]*/\)$|\1|p' "$work/out" | head -n 1)
password=$(sed -n 's/^and sign in with the password \([a-z0-9]*\) (any user name)\.$/\1/p' "$work/out")
[ -n "$url" ] && [ -n "$password" ] || { show; fail "$label printed no address and password"; }
case $url in
  http://localhost:*) echo "::notice::Delivery (server): this computer has no private IPv4 address, so the client reached $label on loopback only" ;;
  http://127.*) fail "$label printed a loopback address, $url, for other computers to open" ;;
esac

tries=0
until [ "$(request page "$url")" = 401 ]; do
  kill -0 "$pid" 2>/dev/null || { show; fail "$label ended before it answered"; }
  tries=$((tries + 1))
  [ "$tries" -lt 120 ] || { show; fail "$label did not answer $url without the password with 401 within 30 seconds"; }
  sleep 0.25
done
echo "ok: $label answers $url, and refuses it without the password"

# Random bytes, by a name with a space and letters beyond ASCII, sent as
# the page's form sends a file, from the page's origin.
name="Été report.bin"
encoded="%C3%89t%C3%A9%20report.bin"
head -c 4096 /dev/urandom >"$work/sent.bin"
code=$(request sent "$url" -u "anyone:$password" -H "Origin: ${url%/}" -F "files[]=@$work/sent.bin;filename=$name")
[ "$code" = 303 ] || { show; fail "$label answered the form that sends a file with $code, not 303"; }
cmp -s "$work/sent.bin" "$home/Drop/$name" || { ls -la "$home/Drop"; fail "the file sent is not in $home/Drop byte for byte"; }
[ "$(find "$home/Drop" -type f | wc -l | tr -d ' ')" = 1 ] || { ls -la "$home/Drop"; fail "$home/Drop holds more than the one file sent"; }
echo "ok: the file sent arrived in $home/Drop byte for byte"

[ "$(request listing "$url" -u "anyone:$password")" = 200 ] || fail "$label did not answer its page with 200"
grep -q "<a href=\"/files/$encoded\">$name</a>" "$work/listing" || fail "$label does not list the file sent"
[ "$(request fetched "${url}files/$encoded" -u "anyone:$password")" = 200 ] || fail "$label did not answer the file's link with 200"
cmp -s "$work/sent.bin" "$work/fetched" || fail "the file fetched is not the file sent"
echo "ok: a second client found the file listed and fetched it byte for byte"

kill -INT "$pid"
# A watchdog ends a server that does not stop; it leaves quietly, with no
# word from the shell, when the server stops first.
(
  trap 'exit 0' TERM
  sleep 10 &
  wait
  kill -KILL "$pid"
) >/dev/null 2>&1 &
watchdog=$!
status=0
wait "$pid" || status=$?
kill "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null || true
pid=
if [ "$status" != 0 ] || [ -s "$work/err" ]; then
  show
  fail "$label ended by SIGINT with status $status, not 0 with nothing on stderr"
fi
echo "ok: SIGINT stopped $label with status 0"
