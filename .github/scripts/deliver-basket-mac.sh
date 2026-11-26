#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Basket on a Mac, built: unpacks what fledge build wrote for
# examples/basket, starts its program with no Ruby on its PATH, and
# fails unless Basket draws its window, adds an item, and removes it.
#
#   deliver-basket-mac.sh ARCHIVE
#
# ARCHIVE is "Basket-arm64-darwin.tar.gz". Two runs of the app's program,
# which the launcher starts as Finder's double-click does, each with a
# separate HOME, so that Basket's list starts empty:
#
# 1. The app as built must log "Basket shows 0 items": Basket's Ruby
#    reached AppKit, made its window, and AppKit called the delegate
#    written in Ruby.
# 2. The app with a driver for its program, which must log "Basket added
#    Milk" and "Basket removed Milk": the driver (deliver-basket-mac.rb)
#    prepares a call that types Milk into the screen's field, presses
#    Add, selects the row, and chooses Edit > Delete, and then loads the
#    app's main.rb. The copy of the app that unpacked here has the driver
#    beside main.rb and its fledge.cfg names the driver as the entry; the
#    launcher, the Ruby, the gems, and Basket's own files are the ones
#    that were built.
#
# The screen is driven from inside because neither way in from outside
# works on every Mac. UI scripting through System Events needs
# Accessibility and Automation permissions that a computer's owner grants
# in a dialog, and an account without them gets errAEEventNotPermitted
# (-1743). And the
# launcher removes RUBYOPT and every other variable that could put a Ruby
# file into the program it starts, so nothing outside can ask the
# launched program to drive itself. Key events that a process sent to
# its own NSApplication did not press the default button when the
# research tried them, so the driver presses Add and Delete as AppKit
# does when they are clicked.
#
# A run that has not ended after 90 seconds fails. The first run ends
# with KILL, since AppKit's run loop never returns to Ruby to take TERM.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
here=$(cd "$(dirname "$0")" && pwd)

fail() {
  echo "::error::Delivery (Basket): $*" >&2
  exit 1
}

work=$(mktemp -d)
cleanup() {
  [ -z "${program_pid:-}" ] || kill "$program_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# Everything below starts from /, as a program Finder starts does.
cd /

place="$work/My Apps"
mkdir -p "$place" "$work/empty-path"
tar -xzf "$archive" -C "$place"
bundle=$(find "$place" -maxdepth 2 -name 'Basket.app' | head -n 1)
[ -n "$bundle" ] || fail "no Basket.app in $(basename "$archive")"
program="$bundle/Contents/MacOS/Basket"
[ -x "$program" ] || fail "$program is not executable after unpacking"
app="$bundle/Contents/Resources/app"
[ -f "$app/main.rb" ] || fail "the app holds no main.rb"
if env -i PATH="$work/empty-path" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi

# wait_for LOG TEXT: waits up to 90 seconds for TEXT to appear in LOG.
wait_for() {
  seconds=0
  until grep -q "$2" "$1" 2>/dev/null; do
    seconds=$((seconds + 1))
    [ "$seconds" -lt 90 ] || return 1
    sleep 1
  done
}

# 1. The app's program, left running until its first line appears, then
# stopped with KILL: AppKit's run loop never returns to Ruby, which
# would take TERM as a request to stop at its next turn.
mkdir "$work/home-start"
env -i PATH="$work/empty-path" HOME="$work/home-start" "$program" >"$work/start.log" 2>&1 &
program_pid=$!
wait_for "$work/start.log" "^Basket shows 0 items$" ||
  fail "its program did not log \"Basket shows 0 items\" in 90 seconds: $(cat "$work/start.log")"
kill -0 "$program_pid" 2>/dev/null || fail "its program ended before it was stopped: $(cat "$work/start.log")"
kill -9 "$program_pid"
wait "$program_pid" 2>/dev/null || true
program_pid=
echo "ok: the app's program drew Basket's window and logged \"$(grep '^Basket shows' "$work/start.log")\""

# 2. The screen, driven by a driver the launcher runs in place of main.rb.
mkdir "$work/home-drive"
cp "$here/deliver-basket-mac.rb" "$app/deliver-basket-mac.rb"
config="$bundle/Contents/Resources/fledge.cfg"
sed 's/^entry = .*/entry = deliver-basket-mac.rb/' "$config" >"$work/fledge.cfg"
cp "$work/fledge.cfg" "$config"
grep -q '^entry = deliver-basket-mac.rb$' "$config" || fail "fledge.cfg has no entry line to give the driver"
env -i PATH="$work/empty-path" HOME="$work/home-drive" "$program" >"$work/drive.log" 2>&1 &
driver=$!
seconds=0
while kill -0 "$driver" 2>/dev/null; do
  seconds=$((seconds + 1))
  if [ "$seconds" -ge 90 ]; then
    kill -9 "$driver"
    fail "driving the screen took more than 90 seconds: $(cat "$work/drive.log")"
  fi
  sleep 1
done
status=0
wait "$driver" || status=$?
cat "$work/drive.log"
[ "$status" -eq 0 ] || fail "driving the screen exited with $status"
for line in "Basket shows 0 items" "Basket added Milk" "Basket removed Milk"; do
  grep -q "^$line\$" "$work/drive.log" || fail "Basket did not log \"$line\""
done
saved=$(sed -n 's/^Basket keeps its list in //p' "$work/drive.log" | head -n 1)
[ -f "$saved" ] || fail "Basket kept no list at \"$saved\""
[ "$(cat "$saved")" = "[]" ] || fail "Basket's list holds $(cat "$saved"), not []"
echo "ok: Basket added Milk and removed it, and its list in $saved is empty again"
