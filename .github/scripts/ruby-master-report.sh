#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# ruby-master.yml's report: reads each job's result from tmp/results
# (ruby-master-result.sh), writes the night into the body of the one
# issue titled "Ruby's master: nightly status", opening it the first
# night, and fails when the night is news (tasks/ruby_master_status.rb).
#
#   ruby-master-report.sh JOB...
#
# JOB names every job the night runs; one that recorded no result, as
# one that was cancelled or timed out, counts as failed. REVISION, DATE,
# and RUN name the night; GH_TOKEN and GITHUB_REPOSITORY the issue's
# repository. An edit of the body sends no notification; only the
# issue's opening, and a run that fails, do.
set -euo pipefail

title="Ruby's master: nightly status"
failed=()
for job in "$@"; do
  file="tmp/results/$(printf '%s' "$job" | tr -c 'A-Za-z0-9' '_').txt"
  outcome=$(cat "$file" 2>/dev/null || echo missing)
  [ "$outcome" = success ] || failed+=("$job")
done

number=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "in:title \"$title\"" --json number,title \
  --jq "map(select(.title == \"$title\")) | .[0].number // empty")
body=tmp/ruby-master-status.md
mkdir -p tmp
if [ -n "$number" ]; then
  gh issue view "$number" --repo "$GITHUB_REPOSITORY" --json body --jq .body >"$body"
else
  : >"$body"
fi

status=0
ruby tasks/ruby_master_status.rb "$body" "$REVISION" "$DATE" "$RUN" "${failed[@]}" >/dev/null || status=$?
[ "$status" -eq 0 ] || [ "$status" -eq 3 ] || exit "$status"

if [ -n "$number" ]; then
  gh issue edit "$number" --repo "$GITHUB_REPOSITORY" --body-file "$body" >/dev/null
else
  gh issue create --repo "$GITHUB_REPOSITORY" --title "$title" --body-file "$body"
fi
cat "$body" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
if [ "$status" -eq 3 ]; then
  echo "::error::A job failed on Ruby's master that had not been failing: ${failed[*]}"
  exit 1
fi
