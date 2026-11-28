#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# apt-get update on a GitHub Ubuntu runner, as a step's first line, before
# it installs a package from Ubuntu's archive.
#
#   runner-apt-update.sh
#
# The runner image lists Microsoft's repository, packages.microsoft.com,
# beside Ubuntu's, and apt-get update exits 100 when that host answers
# 403 or does not sign its index, as it did on 2026-11-27 (run
# 45910670171), though no step installs a package from it. This script
# fails on every error and warning but those that name that host, so a
# failure to fetch Ubuntu's own archive still fails the step.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -u

log=$(mktemp)
status=0
{ sudo apt-get update -qq; } >"$log" 2>&1 || status=$?
cat "$log"
[ "$status" -ne 0 ] || exit 0

if grep -E '^[EW]: ' "$log" | grep -qv 'packages\.microsoft\.com'; then
  echo "runner-apt-update.sh: apt-get update exited $status with an error from a host other than packages.microsoft.com" >&2
  exit "$status"
fi
echo "runner-apt-update.sh: apt-get update exited $status, with errors only from packages.microsoft.com, which no step installs from"
