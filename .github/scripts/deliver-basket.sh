#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Basket on Linux, built: unpacks what fledge build wrote for
# examples/basket, starts its program from / with no Ruby on its PATH,
# and uses it as a person does, with real input: types Milk and presses
# Return, then clicks the button that removes the row, and the Undo that
# the toast offers. It fails unless Basket logs where it keeps its list,
# "Basket added Milk", "Basket removed Milk", and "Basket restored Milk",
# and ends with status 0 when it gets SIGTERM, which it takes through
# GLib's main loop (examples/basket/lib/basket/gtk.rb).
#
#   deliver-basket.sh ARCHIVE [without-gtk]
#
# ARCHIVE is "Basket-PLATFORM.tar.gz". The computer needs Xvfb, a window
# manager (Openbox), and xdotool, and, but for without-gtk, GTK 4 and
# libadwaita, Mesa's drivers, and a font. With without-gtk, on a computer
# that has no GTK 4, Basket must instead name the library it lacks and
# exit with 72. Each wait is bounded, so a run that hangs fails. When
# BASKET_SHOTS names a folder, the screen is copied there after each
# step, as the X server's framebuffer file, for a person to read.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1

fail() {
  echo "::error::Delivery (Basket): $*" >&2
  [ ! -s "${log:-/dev/null}" ] || { echo "--- Basket's output"; cat "$log"; } >&2
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
log="$work/basket.log"
# Where Basket keeps its list: XDG's data folder, $HOME/.local/share, since
# the clean environment below sets no XDG_DATA_HOME.
list="$work/home/.local/share/basket/basket.json"

place="$work/My Apps"
mkdir -p "$place" "$work/empty-path" "$work/home" "$work/runtime"
chmod 700 "$work/runtime"
tar -xzf "$archive" -C "$place"
program=$(find "$place" -maxdepth 2 -type f -name Basket | head -n 1)
[ -n "$program" ] && [ -x "$program" ] || fail "no program of Basket in $(basename "$archive")"
if env -i PATH="$work/empty-path" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi

# basket [VARIABLE=VALUE]...: becomes Basket's program, from /, in a
# clean environment with no Ruby on its PATH, so a caller runs it in a
# subshell, and its $! is Basket's process.
basket() {
  cd / && exec env -i PATH="$work/empty-path" HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" NO_AT_BRIDGE=1 "$@" "$program"
}

if [ "${2:-}" = without-gtk ]; then
  if ldconfig -p | grep -q 'libgtk-4.so.1'; then
    fail "this computer has GTK 4 before the test begins"
  fi
  status=0
  out=$(basket 2>&1) || status=$?
  echo "without GTK 4: $out"
  [ "$status" -eq 72 ] || fail "without GTK 4 its program exited with $status, not 72"
  printf '%s' "$out" | grep -q '^Basket needs libgtk-4.so.1, which this computer does not have' ||
    fail "without GTK 4 its program did not name the library it lacks"
  echo "ok: without GTK 4 Basket names libgtk-4.so.1 and exits with 72"
  exit 0
fi

# wait_for PATTERN: until the log holds a line that is exactly PATTERN, or
# for 20 seconds.
wait_for() {
  tries=0
  until grep -qx "$1" "$log" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -le 80 ] || fail "Basket did not log \"$1\" in 20 seconds"
    kill -0 "$app" 2>/dev/null || fail "Basket ended before it logged \"$1\""
    sleep 0.25
  done
  echo "ok: Basket logged \"$1\""
}

# shot NAME: a copy of the screen, when BASKET_SHOTS asks for it.
shot() {
  [ -z "${BASKET_SHOTS:-}" ] || { sleep 1; cp "$work/framebuffer/Xvfb_screen0" "$BASKET_SHOTS/$1.xwd"; }
}

mkdir -p "$work/framebuffer"
display=300
while [ -e "/tmp/.X$display-lock" ]; do display=$((display + 1)); done
Xvfb ":$display" -screen 0 800x640x24 -nolisten tcp -fbdir "$work/framebuffer" >"$work/xvfb.log" 2>&1 &
xvfb=$!
export DISPLAY=":$display"
tries=0
until xdotool getdisplaygeometry >/dev/null 2>&1; do
  tries=$((tries + 1))
  [ "$tries" -le 40 ] || fail "Xvfb did not start: $(cat "$work/xvfb.log")"
  sleep 0.25
done
openbox >"$work/openbox.log" 2>&1 &
wm=$!
sleep 1

basket DISPLAY="$DISPLAY" >"$log" 2>&1 &
app=$!
window=$(timeout 30 xdotool search --sync --onlyvisible --name '^Basket$' | head -n 1) || true
[ -n "$window" ] || fail "Basket opened no window named Basket in 30 seconds"
wait_for "Basket keeps its list in $list"
wait_for "Basket shows 0 items"
sleep 1
eval "$(xdotool getwindowgeometry --shell "$window")"
echo "ok: Basket's window is ${WIDTH}x${HEIGHT} at $X,$Y"
shot 1-empty

# The entry, in the first row under the header bar: click it, type, and
# press Return.
entry_x=$((X + 60))
entry_y=$((Y + 76))
xdotool mousemove "$entry_x" "$entry_y" click 1
xdotool type --delay 80 Milk
xdotool key Return
wait_for "Basket added Milk"
shot 2-added

# The button at the end of Milk's row, the first of the list.
xdotool mousemove $((X + WIDTH - 40)) $((Y + 128)) click 1
wait_for "Basket removed Milk"
shot 3-removed

[ "$(cat "$list")" = "[]" ] || fail "the list is $(cat "$list"), not []"
echo "ok: the list is empty again"

# The toast's Undo button, at the bottom of the window, puts Milk back. A
# person looks at the toast before they reach for its button, and the
# script waits for it likewise: a pointer that moves onto the button while
# the toast is still appearing is a click that does nothing, every time on
# a fresh start, where the same move and click two seconds after the toast
# appears restores Milk. The toast stays five seconds.
sleep 2
xdotool mousemove $((X + 300)) $((Y + 467)) click 1
wait_for "Basket restored Milk"
shot 4-restored
[ "$(cat "$list")" = '["Milk"]' ] || fail "the list is $(cat "$list"), not [\"Milk\"]"
echo "ok: the list holds Milk again"

# SIGTERM ends Basket through GLib's main loop, as a desktop's logout
# or a terminal's kill does, with status 0.
kill "$app"
tries=0
while kill -0 "$app" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -le 20 ] || fail "Basket was still running 5 seconds after SIGTERM"
  sleep 0.25
done
status=0
wait "$app" || status=$?
app=
[ "$status" -eq 0 ] || fail "Basket exited with $status after SIGTERM, not 0"
echo "ok: SIGTERM ended Basket with status 0"
echo "Delivered: Basket added Milk, removed it, restored it, and ended cleanly"
