#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of examples/lectern on macOS and Linux: unpacks
# "Lectern-PLATFORM.tar.gz" in a folder whose name has a space and
# characters outside ASCII, and runs Lectern on SAMPLE, a Markdown file,
# from / in an empty environment, with no Ruby on PATH. What it prints
# must be what bundle exec ruby main.rb printed on the Build job: PLAIN
# for the output of a pipe, and COLORED for --color=always, which holds
# Rouge's highlighting and every other style. It also reads the standard
# input, and a file it cannot read and an option it does not know end it
# with sysexits.h's EX_NOINPUT and EX_USAGE.
#
#   deliver-lectern.sh ARCHIVE SAMPLE PLAIN COLORED
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1
sample=$2
plain=$3
colored=$4

fail() {
  echo "::error::Delivery (lectern): $*" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place" "$work/empty-path"
tar -xzf "$archive" -C "$place"
root="$place/$(basename "$archive" .tar.gz)"
app="$root/Lectern"
[ -x "$app" ] || fail "$app is not in the archive"
cp "$sample" "$work/notes.md"
esc=$(printf '\033')

# lectern ARGUMENT...: runs Lectern as a person's shell does, with no
# Ruby on PATH, leaving its standard output in $work/out, its standard
# error in $work/err, and its exit status in $work/status.
lectern() {
  status=0
  (cd / && env -i PATH="$work/empty-path" HOME="$work" LC_ALL=C.UTF-8 "$app" "$@") >"$work/out" 2>"$work/err" || status=$?
  echo "$status" >"$work/status"
}

lectern "$work/notes.md"
[ "$(cat "$work/status")" -eq 0 ] || { cat "$work/err"; fail "Lectern exited with $(cat "$work/status")"; }
[ ! -s "$work/err" ] || { cat "$work/err"; fail "Lectern wrote to standard error"; }
cmp -s "$work/out" "$plain" || { diff "$plain" "$work/out" || true; fail "Lectern printed other text than bundle exec"; }
if grep -q "$esc" "$work/out"; then fail "Lectern wrote an escape sequence to a pipe"; fi
echo "ok: Lectern prints plain text to a pipe, as bundle exec does"

lectern --color=always "$work/notes.md"
[ "$(cat "$work/status")" -eq 0 ] || { cat "$work/err"; fail "Lectern --color=always exited with $(cat "$work/status")"; }
cmp -s "$work/out" "$colored" || { diff "$colored" "$work/out" || true; fail "Lectern printed other colors than bundle exec"; }
grep -q "${esc}\[90;3m" "$work/out" || fail "the colored output has no highlighted code"
echo "ok: Lectern draws headings, emphasis, tables, and highlighted code as bundle exec does"

status=0
(cd / && env -i PATH="$work/empty-path" HOME="$work" LC_ALL=C.UTF-8 "$app" - <"$work/notes.md") >"$work/out" 2>"$work/err" || status=$?
[ "$status" -eq 0 ] || { cat "$work/err"; fail "Lectern - exited with $status"; }
cmp -s "$work/out" "$plain" || { diff "$plain" "$work/out" || true; fail "Lectern - printed other text than a file's"; }
echo "ok: Lectern reads the standard input as it reads a file"

for case in "66 No such file or directory $work/missing.md" "64 invalid option: --nope"; do
  want=${case%% *}
  argument=${case##* }
  lectern "$argument"
  status=$(cat "$work/status")
  [ "$status" -eq "$want" ] || { cat "$work/err"; fail "Lectern $argument exited with $status, not $want"; }
  reason=${case#* }
  reason=${reason% *}
  grep -qF "$reason" "$work/err" || { cat "$work/err"; fail "Lectern $argument did not say: $reason"; }
done
echo "ok: Lectern exits 66 on a file it cannot read and 64 on an option it does not know"

echo "Delivered: Lectern"
