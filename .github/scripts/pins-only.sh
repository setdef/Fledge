#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Prints true when the commit checked out is a pin commit (ADR 014): it
# has one parent, and lib/fledge/SHA256SUMS is the only file it changes
# from it. Prints false for anything else, a merge, a first commit, or a
# clone too shallow to hold the parent (actions/checkout needs
# fetch-depth: 2), so a commit is given the short CI only when it is
# certainly a pin commit.
#
#   .github/scripts/pins-only.sh
set -eu

if git rev-parse --quiet --verify 'HEAD^2' > /dev/null || ! git rev-parse --quiet --verify 'HEAD^' > /dev/null; then
  echo false
elif [ "$(git diff --name-only 'HEAD^' HEAD)" = lib/fledge/SHA256SUMS ]; then
  echo true
else
  echo false
fi
