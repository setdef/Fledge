#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of a server (examples/roda_server, Jot, a notes board served
# on 127.0.0.1) on macOS or Linux: unpacks ARCHIVE, Jot-PLATFORM.tar.gz,
# makes the unpacked app read-only, as /Applications or an AppImage's
# mount leaves it, and runs it from / with no Ruby of the computer
# reachable, as a person starts it, and checks that:
#
#   - it listens on 127.0.0.1 alone, at port 8765, and answers its page;
#   - a note sent as its form sends it is listed on the page, and kept in
#     the person's data folder (Application Support on macOS, the XDG
#     data folder on Linux), not in the app;
#   - Ctrl-C's signal, SIGINT, stops it with status 0, after it says so;
#   - started again, it lists the note it kept;
#   - a second start while it runs says the port is taken and ends with
#     69 (EX_UNAVAILABLE), and TERM stops the first with status 0.
#
# It sends SIGINT to the app's process, which is what a terminal's Ctrl-C
# delivers to it (deliver-console.sh shows a terminal's own Ctrl-C reach
# a Fledge app as it reaches ruby). No request leaves the computer.
#
#   deliver-server.sh ARCHIVE
#   deliver-server.sh --reference COMMAND...
#
# With --reference, it runs COMMAND, such as bundle exec ruby main.rb in
# the example's folder, in place of the app, with no read-only folder,
# and expects exactly the same; the integration test runs both. It asks
# with curl, or with BusyBox's wget where curl is missing, as on Alpine.
# PORT sets another port than 8765.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

fail() {
  echo "::error::Delivery (server): $*" >&2
  exit 1
}

port=${PORT:-8765}
url="http://127.0.0.1:$port/"
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
  set -- env HOME="$home" XDG_DATA_HOME= "$@"
  label="the reference"
else
  archive=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  folder=$(basename "$archive" .tar.gz)
  mkdir -p "$work/apps"
  tar -xzf "$archive" -C "$work/apps"
  app="$work/apps/$folder/Jot"
  [ -x "$app" ] || fail "$app is not executable after unpacking"
  chmod -R a-w "$work/apps"
  set -- env -i PATH="$work/empty-path" HOME="$home" "$app"
  label="the built app"
fi

case $(uname -s) in
  Darwin) data="$home/Library/Application Support/Jot" ;;
  *) data="$home/.local/share/jot" ;;
esac

# start COMMAND...: starts the server from / in the background, with
# HOME the work folder's, and waits until it says it listens.
start() {
  (cd / && exec "$@" --port "$port" --no-browser) >"$work/$name.out" 2>"$work/$name.err" &
  pid=$!
  tries=0
  until grep -q "^Jot is at $url\$" "$work/$name.out" 2>/dev/null; do
    kill -0 "$pid" 2>/dev/null || { cat "$work/$name.out" "$work/$name.err"; fail "$label ($name) ended before it listened"; }
    tries=$((tries + 1))
    [ "$tries" -lt 120 ] || { cat "$work/$name.out" "$work/$name.err"; fail "$label ($name) did not say it listened within 30 seconds"; }
    sleep 0.25
  done
}

# stop SIGNAL: sends SIGNAL to the server and fails unless it ends with
# status 0 within 10 seconds, saying where the notes are.
stop() {
  kill -"$1" "$pid"
  # A watchdog ends a server that does not stop; it leaves quietly,
  # with no word from the shell, when the server stops first.
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
  expected="Jot is at $url
Press Ctrl-C to stop it.
Jot stopped. Your notes are in $data"
  if [ "$status" != 0 ] || [ "$(cat "$work/$name.out")" != "$expected" ] || [ -s "$work/$name.err" ]; then
    echo "--- stdout"; cat "$work/$name.out"; echo "--- stderr"; cat "$work/$name.err"
    fail "$label ($name) ended by SIG$1 with status $status, not 0 with what it printed above"
  fi
  echo "ok ($name): SIG$1 stopped $label with status 0"
}

# ask PATH [FORM]: the page at PATH, or the page after sending FORM to
# PATH as the page's form does, into $work/page; fails on any status but
# 200, after the redirect a form gets.
ask() {
  if command -v curl >/dev/null; then
    if [ $# = 2 ]; then
      curl -fsSL -o "$work/page" -H "Origin: http://127.0.0.1:$port" --data "$2" "http://127.0.0.1:$port$1"
    else
      curl -fsS -o "$work/page" "http://127.0.0.1:$port$1"
    fi
  elif [ $# = 2 ]; then
    wget -q -O "$work/page" --header "Origin: http://127.0.0.1:$port" --post-data "$2" "http://127.0.0.1:$port$1"
  else
    wget -q -O "$work/page" "http://127.0.0.1:$port$1"
  fi || fail "$label ($name) did not answer $1 with 200"
}

# listening: fails unless the server listens on 127.0.0.1 at the port,
# and on no other address.
listening() {
  case $(uname -s) in
    Darwin) addresses=$(lsof -nP -a -p "$pid" -iTCP:"$port" -sTCP:LISTEN -Fn 2>/dev/null | sed -n 's/^n//p') ;;
    *)
      hex=$(printf '%04X' "$port")
      addresses=$(awk -v hex="$hex" '$4 == "0A" && $2 ~ ":" hex "$" { print $2 }' /proc/net/tcp /proc/net/tcp6 |
        sed 's/^0100007F:.*/127.0.0.1:'"$port"'/')
      ;;
  esac
  [ "$addresses" = "127.0.0.1:$port" ] || fail "$label ($name) listens on '$addresses', not on 127.0.0.1:$port alone"
  echo "ok ($name): listens on 127.0.0.1:$port alone"
}

name=first
start "$@"
listening
ask /
grep -q '<p>No notes yet.</p>' "$work/page" || fail "$label ($name): the first page does not say there are no notes"
ask /notes "text=Ask+Ana+about+the+%C3%A9t%C3%A9+rota"
grep -q '<li><p>Ask Ana about the été rota</p>' "$work/page" || fail "$label ($name) does not list the note sent to it"
echo "ok ($name): answered the page, and listed the note sent to it"
stop INT
[ -s "$data/notes.json" ] || fail "$label kept no notes.json in $data"
echo "ok: the note is in $data/notes.json"

name=again
start "$@"
ask /
grep -q '<li><p>Ask Ana about the été rota</p>' "$work/page" || fail "$label ($name) does not list the note it kept"
echo "ok ($name): listed the note it kept"
first=$pid
status=0
(cd / && exec "$@" --port "$port" --no-browser) >"$work/taken.out" 2>"$work/taken.err" || status=$?
if [ "$status" != 69 ] || ! grep -q "^Jot cannot start: port $port is in use" "$work/taken.err"; then
  cat "$work/taken.out" "$work/taken.err"
  fail "$label, started on a taken port, exited with $status, not 69 with its reason"
fi
echo "ok (taken): a second start said the port is in use and exited with 69"
pid=$first
stop TERM
