#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of one project's several programs (ADR 024) on macOS and
# Linux: unpacks what fledge build wrote for examples/programs, checks
# that the folder holds one copy of the project and one Ruby, and runs
# both programs from it, with no Ruby anywhere they can reach.
#
#   deliver-programs.sh ARCHIVE
#
# ARCHIVE is "Shared Save-PLATFORM.tar.gz". It holds a windowed program,
# Shared Save, and a console one, shared-save: on Linux both sit at the
# folder's top; on macOS the console one lives in Shared Save.app's
# Contents/MacOS, linked from the folder, and codesign must verify the
# bundle strictly and deeply with it inside. The console program prints
# each entry of the save it is given and adds its own; the windowed one
# writes what it read to a report and adds its own. Each entry names the
# real path of the project and of Ruby's library the program ran, which
# must be the same for both, inside the folder.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1
windowed="Shared Save"
console=shared-save

fail() {
  echo "::error::Delivery (programs): $*" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
archive=$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")
folder=$(basename "$archive" .tar.gz)
place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place"
tar -xzf "$archive" -C "$place"
root="$place/$folder"
real_root=$(cd "$root" && pwd -P)

empty="$work/empty-path"
mkdir -p "$empty"

case "$(uname -s)" in
  Darwin)
    bundle="$root/$windowed.app"
    windowed_program="$bundle/Contents/MacOS/$windowed"
    console_program="$root/$console"
    [ -L "$console_program" ] || fail "$console is not a link beside $windowed.app"
    [ "$(readlink "$console_program")" = "$windowed.app/Contents/MacOS/$console" ] ||
      fail "$console links to $(readlink "$console_program"), not into $windowed.app"
    codesign --verify --strict --deep --verbose=2 "$bundle" 2>"$work/codesign" || { cat "$work/codesign"; fail "codesign does not verify $windowed.app"; }
    grep -q "MacOS/$console" "$work/codesign" || { cat "$work/codesign"; fail "the bundle's signature does not cover $console"; }
    echo "ok: codesign verifies $windowed.app, with $console inside it"
    ;;
  Linux)
    windowed_program="$root/$windowed"
    console_program="$root/$console"
    ;;
  *) fail "no delivery of programs for $(uname -s)" ;;
esac
[ -x "$windowed_program" ] || fail "$windowed is not executable after unpacking"
[ -x "$console_program" ] || fail "$console is not executable after unpacking"

# One project and one Ruby: each file of either is in the folder once.
for file in window.rb shared_save.rb fledge.yml rbconfig.rb; do
  count=$(find "$root" -name "$file" -type f | wc -l | tr -d ' ')
  [ "$count" = 1 ] || fail "the folder holds $count copies of $file, not one"
done
echo "ok: the folder holds one project and one Ruby"

save="$work/save.jsonl"
report="$work/report.json"

# run LABEL PROGRAM ARGS...: runs PROGRAM from / in an empty environment,
# and fails unless it exits with 0 and writes nothing to standard error.
run() {
  label=$1
  shift
  set +e
  (cd / && env -i PATH="$empty" HOME="$work" "$@") >"$work/out" 2>"$work/err"
  status=$?
  set -e
  [ "$status" -eq 0 ] || { cat "$work/out" "$work/err"; fail "$label: exit status $status, not 0"; }
  [ ! -s "$work/err" ] || { cat "$work/err"; fail "$label: it wrote to standard error"; }
}

run "$console, first" "$console_program" "$save"
[ ! -s "$work/out" ] || { cat "$work/out"; fail "$console found entries in a save that was not there"; }
run "$windowed" "$windowed_program" "$save" "$report"
grep -q '^{"read":\[{"by":"shared-save",' "$report" || fail "$windowed did not read what $console saved: $(cat "$report")"
echo "ok: $windowed read what $console saved"
run "$console, again" "$console_program" "$save"
[ "$(wc -l <"$work/out" | tr -d ' ')" = 2 ] || { cat "$work/out"; fail "$console did not find two entries in the save"; }
sed -n 2p "$work/out" | grep -q "^{\"by\":\"$windowed\"," || { cat "$work/out"; fail "$console did not read what $windowed saved"; }
echo "ok: $console read what $windowed saved"

# The project and the Ruby each program ran, which must be one of each,
# in the folder.
for key in project ruby; do
  values=$(sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p" "$work/out" | sort -u)
  [ "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" = 1 ] || fail "the programs ran different ${key}s: $values"
  case "$values" in
    "$real_root"/*) echo "ok: both programs ran the $key at ${values#"$real_root"/}" ;;
    *) fail "the $key, $values, is not in the folder, $real_root" ;;
  esac
done

# A copy renamed by hand finds no program of its name.
renamed="$(dirname "$windowed_program")/renamed"
cp "$windowed_program" "$renamed"
set +e
(cd / && env -i PATH="$empty" HOME="$work" "$renamed" "$save" "$report") >"$work/out" 2>"$work/err"
status=$?
set -e
[ "$status" -eq 66 ] || { cat "$work/err"; fail "a renamed program exited with $status, not 66"; }
grep -q "has no program named renamed" "$work/err" || { cat "$work/err"; fail "a renamed program did not say what it was missing"; }
echo "ok: a renamed program exits with 66: $(cat "$work/err")"

echo "Delivered: $windowed and $console, from one folder"
