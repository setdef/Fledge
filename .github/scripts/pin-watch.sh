#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# pin-watch.yml's one step: runs tasks/pin_watch.rb, prints what it
# found, adds it to the run's summary, and keeps it as
# tmp/pin-watch.json. A pin with a newer release (the script's status 3)
# passes, as every pin current does; an upstream that could not be read
# (1) fails. GITHUB_TOKEN, when set, is the token GitHub's API is asked
# with; GITHUB_STEP_SUMMARY, when set, the summary written to; and
# GITHUB_OUTPUT, when set, gets behind=true when a pin is behind.
set -euo pipefail

mkdir -p tmp
status=0
ruby tasks/pin_watch.rb tmp/pin-watch.json >tmp/pin-watch.txt || status=$?
cat tmp/pin-watch.txt
{
  echo '```'
  cat tmp/pin-watch.txt
  echo '```'
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
if [ "$status" -eq 3 ]; then behind=true; else behind=false; fi
echo "behind=$behind" >>"${GITHUB_OUTPUT:-/dev/null}"
[ "$status" -eq 0 ] || [ "$status" -eq 3 ] || exit "$status"
