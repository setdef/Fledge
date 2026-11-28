#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of Pop, the Lota game of examples/lota_pop, on macOS and
# Linux: unpacks what fledge build wrote, starts its program from / in an
# empty environment with no Ruby on its PATH, and plays it as far as the
# computer lets a script play. Pop prints its score and quits when
# POP_QUIT_AFTER seconds have passed (examples/lota_pop/game/main.rb), so
# a run that ends by itself with status 0 and the line "Pop: N popped"
# says that Lota opened its window and drew frames through the app's own
# Ruby, SDL3, and OpenGL, that its update callback ran for the seconds
# asked, and that Lota ended the game and the process cleanly.
#
#   deliver-pop.sh ARCHIVE
#
# ARCHIVE is "Pop-PLATFORM.tar.gz". On macOS the app runs through its
# own program and through open -W, as Finder starts it, each popping
# nothing, so each must print "Pop: 0 popped": a script cannot click a
# window on a Mac, since that takes Accessibility permission only the
# computer's owner gives in a dialog, and the launcher removes what
# could put a driver into the program (deliver-basket-mac.sh says so
# at length). On Linux the app runs on the display DISPLAY names, or on
# an Xvfb of its own when none is named, and with a window manager
# (Openbox) and xdotool the script does what a person does: it clicks
# every 48 pixels of the window, which lies within a dot's radius of
# each dot, so that the game must print a score of 1 or more. The
# computer then needs Xvfb, Openbox, xdotool, Mesa's drivers, and a
# font. A run that has not ended after 90 seconds fails.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1

fail() {
  echo "::error::Delivery (Pop): $*" >&2
  [ ! -s "${work:-/dev/null}/err" ] || { echo "--- Pop's standard error"; cat "$work/err"; } >&2
  exit 1
}

work=$(mktemp -d)
cleanup() {
  for pid in "${app:-}" "${wm:-}" "${xvfb:-}"; do
    [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  done
  rm -rf "$work"
}
trap cleanup EXIT
os=$(uname -s)

archive=$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")
place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place" "$work/empty-path"
tar -xzf "$archive" -C "$place"
case $os in
  Darwin)
    bundle=$(find "$place" -maxdepth 2 -name 'Pop.app' | head -n 1)
    program="$bundle/Contents/MacOS/Pop"
    ;;
  *) program=$(find "$place" -maxdepth 2 -type f -name Pop | head -n 1) ;;
esac
[ -n "$program" ] && [ -f "$program" ] || fail "no program of Pop in $(basename "$archive")"
if env -i PATH="$work/empty-path" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi

# wait_for PID SECONDS: until PID has ended, or fails after SECONDS.
wait_for() {
  tries=0
  while kill -0 "$1" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -le $(($2 * 4)) ] || fail "Pop had not ended after $2 seconds"
    sleep 0.25
  done
}

# check_score LABEL MINIMUM
check_score() {
  [ "$(cat "$work/status")" -eq 0 ] || fail "$1 exited with $(cat "$work/status")"
  # OpenAL says "Could not open device." on a computer with no sound
  # card, so the score is the one line that is "Pop: N popped".
  line=$(grep -x 'Pop: [0-9][0-9]* popped' "$work/out" | head -n 1) || true
  [ -n "$line" ] || fail "$1 printed no line 'Pop: N popped': $(cat "$work/out")"
  score=${line#Pop: }
  score=${score% popped}
  [ "$score" -ge "$2" ] 2>/dev/null || fail "$1 printed a score of $score, under $2"
  echo "ok: $1 ended with status 0 and printed '$line'"
}

# pop SECONDS [VARIABLE=VALUE]...: becomes Pop's program from /, in a
# clean environment with no Ruby on PATH, so a caller runs it in a
# subshell, and its $! is Pop's process.
pop() {
  seconds=$1
  shift
  cd / && exec env -i PATH="$work/empty-path" HOME="$work" LC_ALL=C.UTF-8 POP_QUIT_AFTER="$seconds" ALSOFT_DRIVERS=null "$@" "$program"
}

if [ "$os" = Darwin ]; then
  status=0
  (pop 3 >"$work/out" 2>"$work/err") & app=$!
  wait "$app" || status=$?
  app=
  echo "$status" >"$work/status"
  check_score "its own program" 0

  # As Finder starts it, with the variable and the file for its output
  # that open passes on.
  status=0
  (cd / && env -i PATH="$work/empty-path" HOME="$work" /usr/bin/open -n -W --env POP_QUIT_AFTER=3 --env ALSOFT_DRIVERS=null --stdout "$work/out" --stderr "$work/err" "$bundle") & app=$!
  wait "$app" || status=$?
  app=
  echo "$status" >"$work/status"
  check_score "open -W" 0
  echo "Delivered: Pop"
  exit 0
fi

mkdir -p "$work/runtime"
chmod 700 "$work/runtime"
if [ -z "${DISPLAY:-}" ]; then
  display=300
  while [ -e "/tmp/.X$display-lock" ]; do display=$((display + 1)); done
  Xvfb ":$display" -screen 0 1024x768x24 -nolisten tcp >"$work/xvfb.log" 2>&1 &
  xvfb=$!
  DISPLAY=":$display"
  export DISPLAY
  tries=0
  until xdotool getdisplaygeometry >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -le 40 ] || fail "Xvfb did not start: $(cat "$work/xvfb.log")"
    sleep 0.25
  done
fi
openbox >"$work/openbox.log" 2>&1 &
wm=$!
sleep 1

# Forty seconds, fewer than 90. The dots need six seconds to show, and
# the sweep of 130 clicks then takes about thirteen more on a runner of
# either architecture (run 46102839557 on both, run 46108351720 on
# aarch64), so a game that quit after twelve seconds ended four seconds
# into the sweep, which then reached only the top rows: a run scored 0
# when no dot fell there. Forty leaves the sweep twice the time it takes.
(pop 40 DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$work/runtime" >"$work/out" 2>"$work/err") & app=$!
tries=0
window=
while [ -z "$window" ]; do
  # The window is the visible one that Pop's process made, which X
  # reports through _NET_WM_PID, whatever its title says.
  window=$(xdotool search --onlyvisible --pid "$app" | head -n 1) || true
  [ -z "$window" ] || break
  tries=$((tries + 1))
  if ! kill -0 "$app" 2>/dev/null || [ "$tries" -gt 120 ]; then
    for each in $(xdotool search --onlyvisible --name '' 2>/dev/null); do
      echo "visible window $each: '$(xdotool getwindowname "$each")' of process $(xdotool getwindowpid "$each" 2>&1), Pop is process $app" >&2
    done
    fail "Pop showed no window in 30 seconds, or ended before it did: $(cat "$work/out")"
  fi
  sleep 0.25
done
eval "$(xdotool getwindowgeometry --shell "$window")"
echo "ok: Pop's window is ${WIDTH}x${HEIGHT} at $X,$Y"

# A dot appears each second, up to five; after six seconds there are
# five, and the sweep, which a click at a time pops any dot within 36
# pixels, runs at once.
sleep 6
clicks=""
y=24
while [ "$y" -lt "$HEIGHT" ]; do
  x=24
  while [ "$x" -lt "$WIDTH" ]; do
    clicks="$clicks mousemove $((X + x)) $((Y + y)) click 1"
    x=$((x + 48))
  done
  y=$((y + 48))
done
# shellcheck disable=SC2086
xdotool $clicks
echo "ok: the sweep clicked the window"

wait_for "$app" 60
status=0
wait "$app" || status=$?
app=
echo "$status" >"$work/status"
check_score "Pop" 1
echo "Delivered: Pop popped a dot and ended cleanly"
