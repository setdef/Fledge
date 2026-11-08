#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Runs the command a package manager installed, as someone with no Ruby
# would: with a PATH that holds only FOLDER, and an otherwise empty
# environment. It must print hello's line, pass on its exit status, and
# leave no ruby command beside it.
#
#   package-manager-check.sh FOLDER RUBY_PLATFORM
#
# This is POSIX sh on purpose: an Arch container runs it too.

set -eu

folder=$1
platform=$2

fail() {
  echo "::error::$*" >&2
  exit 1
}

if env -i PATH="$folder" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "a ruby command is on PATH in $folder"
fi

output=$(env -i PATH="$folder" HOME="$HOME" hello) || fail "hello exited with $?"
echo "$output"
echo "$output" | grep -Eq "^Hello from Ruby [0-9]+\.[0-9]+\.[0-9]+ on $platform\$" || fail "hello printed: $output"

status=0
env -i PATH="$folder" HOME="$HOME" hello 3 >/dev/null || status=$?
[ "$status" -eq 3 ] || fail "hello 3 exited with $status"
