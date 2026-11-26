#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of Focus Timer, the work timer of examples/libui_app, on macOS
# and Linux: unpacks what fledge build wrote, starts its program from / in
# an empty environment with no Ruby on its PATH, and uses it as far as
# the computer lets a script use it. Focus Timer writes no report, as the
# LibUI probe does (deliver-libui.sh), since a timer that reports nothing
# of itself is the app a person runs; so the script reads what the system
# shows of it.
#
#   deliver-focus-timer.sh ARCHIVE LIBRARY
#
# ARCHIVE is "Focus Timer-PLATFORM.tar.gz"; LIBRARY is the file of
# libui-ng's library LibUI opens there, such as libui.arm64.dylib, which
# the app must hold. On Linux, on an Xvfb of its own (or the display
# DISPLAY names) with a window manager (Openbox) and the distribution's
# GTK 3, the window must be titled "Focus Timer (Focus)"; it must stay
# still while the timer is paused, which the X server's framebuffer shows
# as two copies that are equal; after the script presses Start, with the
# keyboard, as a person does, the framebuffer must change, since the
# clock counts down and the progress bar moves, which only Ruby's
# callbacks, through LibUI, do; and Alt+F4 must close the window and end
# the program with status 0, as the window's handler quits LibUI's loop.
# The computer needs Xvfb, Openbox, xdotool, GTK 3, and a font. On macOS
# the app runs through its own program, and the script asks the window
# server, through JavaScript for Automation, for a window of the
# program's process of the width the app asks for (320 points) and its height (160) with a title bar;
# macOS gives a script no way to press the window's buttons or to quit
# the app without the Accessibility and Automation permissions that
# the computer's owner grants in a dialog, so the script stops it with
# SIGTERM, which ends it with status 143, and through open -W as Finder
# starts it. A run that has not ended after 90 seconds fails.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1
library=$2

fail() {
  echo "::error::Delivery (Focus Timer): $*" >&2
  [ ! -s "${work:-/dev/null}/err" ] || { echo "--- Focus Timer's standard error"; cat "$work/err"; } >&2
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
    bundle=$(find "$place" -maxdepth 2 -name 'Focus Timer.app' | head -n 1)
    program="$bundle/Contents/MacOS/Focus Timer"
    ;;
  *) program=$(find "$place" -maxdepth 2 -type f -name 'Focus Timer' | head -n 1) ;;
esac
[ -n "$program" ] && [ -f "$program" ] || fail "no program of Focus Timer in $(basename "$archive")"
found=$(find "$place" -name "$library" | head -n 1)
[ -n "$found" ] || fail "the app holds no $library"
echo "ok: the app holds ${found#"$place/"}"
if env -i PATH="$work/empty-path" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi

# timer [VARIABLE=VALUE]...: becomes Focus Timer's program from /, in a
# clean environment with no Ruby on PATH, so a caller runs it in a
# subshell, and its $! is the program's process.
timer() {
  cd / && exec env -i PATH="$work/empty-path" HOME="$work" LC_ALL=C.UTF-8 "$@" "$program"
}

# gone PID SECONDS: until PID has ended, or fails after SECONDS.
gone() {
  tries=0
  while kill -0 "$1" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -le $(($2 * 4)) ] || fail "Focus Timer was still running $2 seconds after it was asked to end"
    sleep 0.25
  done
}

if [ "$os" = Darwin ]; then
  (timer >"$work/out" 2>"$work/err") & app=$!
  # The window server's list of windows, of every process: the program's
  # own, 320 points wide and 160 to 220 high with its title bar, must be among them.
  tries=0
  until osascript -l JavaScript -e "
    ObjC.import('CoreGraphics');
    var list = ObjC.deepUnwrap(ObjC.castRefToObject(\$.CGWindowListCopyWindowInfo(\$.kCGWindowListOptionAll, 0)));
    var mine = list.filter(function (w) { return w.kCGWindowOwnerPID === $app && w.kCGWindowBounds.Width === 320 && w.kCGWindowBounds.Height >= 160 && w.kCGWindowBounds.Height <= 220; });
    if (mine.length === 0) { throw new Error('no window'); }
  " >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -le 60 ] || fail "the window server shows no 320 point wide window of Focus Timer in 30 seconds"
    kill -0 "$app" 2>/dev/null || fail "Focus Timer ended before it showed a window"
    sleep 0.5
  done
  echo "ok: the window server shows Focus Timer's 320 point wide window"
  sleep 3
  kill -0 "$app" 2>/dev/null || fail "Focus Timer ended by itself within three seconds of its window"
  kill "$app"
  gone "$app" 20
  status=0
  wait "$app" || status=$?
  app=
  [ "$status" -eq 143 ] || fail "SIGTERM ended Focus Timer with $status, not 143"
  echo "ok: SIGTERM ended Focus Timer"

  # As Finder starts it: open -W waits for the app, so it is ended by a
  # timer of the script's own, with the program's pid read from the
  # window server's list.
  (cd / && env -i PATH="$work/empty-path" HOME="$work" /usr/bin/open -n -W "$bundle") & opener=$!
  tries=0
  until pid=$(osascript -l JavaScript -e "
    ObjC.import('CoreGraphics');
    var list = ObjC.deepUnwrap(ObjC.castRefToObject(\$.CGWindowListCopyWindowInfo(\$.kCGWindowListOptionAll, 0)));
    var mine = list.filter(function (w) { return w.kCGWindowOwnerName === 'Focus Timer' && w.kCGWindowBounds.Width === 320 && w.kCGWindowBounds.Height >= 160 && w.kCGWindowBounds.Height <= 220; });
    if (mine.length === 0) { throw new Error('no window'); }
    mine[0].kCGWindowOwnerPID;
  " 2>/dev/null); do
    tries=$((tries + 1))
    [ "$tries" -le 60 ] || { kill "$opener" 2>/dev/null || true; fail "open showed no Focus Timer window in 30 seconds"; }
    sleep 0.5
  done
  echo "ok: open -W showed Focus Timer's window, of process $pid"
  kill "$pid"
  status=0
  wait "$opener" || status=$?
  echo "ok: open -W returned $status once the app ended"
  echo "Delivered: Focus Timer"
  exit 0
fi

mkdir -p "$work/runtime" "$work/framebuffer"
chmod 700 "$work/runtime"
display=300
while [ -e "/tmp/.X$display-lock" ]; do display=$((display + 1)); done
Xvfb ":$display" -screen 0 1024x768x24 -nolisten tcp -fbdir "$work/framebuffer" >"$work/xvfb.log" 2>&1 &
xvfb=$!
DISPLAY=":$display"
export DISPLAY
tries=0
until xdotool getdisplaygeometry >/dev/null 2>&1; do
  tries=$((tries + 1))
  [ "$tries" -le 40 ] || fail "Xvfb did not start: $(cat "$work/xvfb.log")"
  sleep 0.25
done
openbox >"$work/openbox.log" 2>&1 &
wm=$!
sleep 1

(timer DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$work/runtime" NO_AT_BRIDGE=1 >"$work/out" 2>"$work/err") & app=$!
window=$(timeout 30 xdotool search --sync --onlyvisible --name '^Focus Timer' | head -n 1) || true
[ -n "$window" ] || fail "Focus Timer opened no window in 30 seconds"
title=$(xdotool getwindowname "$window")
[ "$title" = "Focus Timer (Focus)" ] || fail "the window is titled '$title', not 'Focus Timer (Focus)'"
echo "ok: the window is titled $title"

# shot NAME: a copy of the screen, as the X server's framebuffer file.
shot() {
  sleep 0.5
  cp "$work/framebuffer/Xvfb_screen0" "$work/$1.xwd"
}

# Paused, the window does not change.
shot paused-1
sleep 2.5
shot paused-2
cmp -s "$work/paused-1.xwd" "$work/paused-2.xwd" || fail "the window changed while the timer was paused"
echo "ok: the window does not change while the timer is paused"

# Start is the first control that takes the keyboard: space presses it.
xdotool windowfocus "$window"
sleep 0.5
xdotool key space
sleep 0.5
shot started-1
sleep 2.5
shot started-2
cmp -s "$work/started-1.xwd" "$work/started-2.xwd" && fail "the window did not change after Start was pressed"
echo "ok: the clock counts down after Start was pressed"

# Alt+F4 closes the window, as Openbox gives it, and the window's
# handler quits LibUI's loop.
xdotool key alt+F4
gone "$app" 20
status=0
wait "$app" || status=$?
app=
[ "$status" -eq 0 ] || fail "Focus Timer exited with $status after its window was closed, not 0"
echo "ok: closing the window ended Focus Timer with status 0"
echo "Delivered: Focus Timer showed its window, counted down, and ended cleanly"
