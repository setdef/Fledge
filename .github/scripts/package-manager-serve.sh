#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Waits until the local server that stands in for a release answers.
#
#   package-manager-serve.sh BASE_URL

set -eu

tries=0
until curl -fsS -o /dev/null "$1/"; do
  tries=$((tries + 1))
  if [ "$tries" -ge 30 ]; then
    echo "::error::nothing answers at $1" >&2
    exit 1
  fi
  sleep 1
done
