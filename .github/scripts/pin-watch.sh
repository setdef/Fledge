#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# pin-watch.yml's one step: runs tasks/pin_watch.rb, prints what it
# found, adds it to the run's summary, and keeps it as
# tmp/pin-watch.json. A pin with a newer release (the script's status 3)
# passes, as every pin current does, and so does a pin held for a person
# that has been behind for no longer than PinWatch::HELD_DAYS; an
# upstream that could not be read, a held pin behind for longer, or a
# line that has ended, its only newer release beyond it for longer than
# PinWatch::BEYOND_DAYS (1), fails. GITHUB_TOKEN, when set, is the token GitHub's API is asked
# with; GITHUB_STEP_SUMMARY, when set, the summary written to; and
# GITHUB_OUTPUT, when set, gets behind=true when a pin nobody holds is
# behind, written before the step fails, so that the move of those pins
# goes on beside the failure.
set -euo pipefail

mkdir -p tmp
rm -f tmp/pin-watch.json
status=0
ruby tasks/pin_watch.rb tmp/pin-watch.json >tmp/pin-watch.txt || status=$?
cat tmp/pin-watch.txt
{
  echo '```'
  cat tmp/pin-watch.txt
  echo '```'
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
behind=false
if [ -f tmp/pin-watch.json ] && jq --exit-status 'any(.[]; .status == "newer")' tmp/pin-watch.json >/dev/null; then
  behind=true
fi
echo "behind=$behind" >>"${GITHUB_OUTPUT:-/dev/null}"
[ "$status" -eq 0 ] || [ "$status" -eq 3 ] || exit "$status"
