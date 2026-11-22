#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# pin-watch.yml's proof of a move (doc/contributors/design/runtimes.md,
# "The proof"). Moves every pin the watch's REPORT found behind, or only
# NAME, with tasks/pin_move.rb, regenerates doc/licensing.md, commits
# the move on top of the checkout, and pushes it to the branch pin-move,
# which only this script writes. It then starts a full run of ci.yml on
# that branch, waits for it, and deletes the branch. Green, it puts the
# move on trunk: as it is when trunk has not moved, and rebased onto
# trunk otherwise, when that rebases cleanly, with a run of ci.yml
# started on trunk to judge the two together, since a push made with
# the workflow's token starts none.
#
#   .github/scripts/pin-prove.sh REPORT [NAME]
#
# It exits 1 when a pin behind could not be moved, after proving the
# rest, and when the proof was red for a single
# pin. A red proof of several pins exits 0 with proven=false in
# GITHUB_OUTPUT, for the workflow to prove each alone. It writes moved,
# the names it moved as JSON, there too, and landed, the commit it put
# on trunk, once that commit's run is green: the proof's own when it
# landed as proven, and when it was rebased, the run it starts on trunk
# and waits for.
#
# PIN_PROVE_LAND=false proves and lands nothing on trunk.
# PIN_PROVE_DRY_RUN=true commits the move in the checkout and stops,
# pushing and starting nothing. GH_TOKEN is the token gh uses.
set -euo pipefail

report=$1
only=${2:-}
branch=pin-move
land=${PIN_PROVE_LAND:-true}
dry=${PIN_PROVE_DRY_RUN:-false}
output=${GITHUB_OUTPUT:-/dev/null}
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
bot=(-c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com")

mkdir -p tmp
rm -f tmp/pin-move-message.txt
args=("$report" --message tmp/pin-move-message.txt)
if [ -n "$only" ]; then args+=(--only "$only"); fi
moving=0
ruby tasks/pin_move.rb "${args[@]}" >tmp/pin-move.txt || moving=$?
cat tmp/pin-move.txt
{
  echo '```'
  cat tmp/pin-move.txt
  echo '```'
} >>"$summary"
moved=$(awk '$1 == "moved" { print $2 }' tmp/pin-move.txt)
count=$(echo "$moved" | grep -c . || true)
echo "moved=$(echo "$moved" | jq --raw-input --null-input --compact-output '[inputs | select(length > 0)]')" >>"$output"
if [ "$count" -eq 0 ]; then
  echo "proven=none" >>"$output"
  exit "$moving"
fi

bundle exec rake licensing
git add --all
git "${bot[@]}" commit --quiet --file tmp/pin-move-message.txt
git log -1 --stat --format='%h %s' | cat
if [ "$dry" = true ]; then
  echo "Dry run: would push $(git rev-parse HEAD) to $branch, run ci.yml there, and land it on trunk: $land"
  exit "$moving"
fi

# Pushes HEAD to the branch, runs ci.yml there, and waits for it; sets
# commit, run, and url, and returns the run's status.
prove() {
  commit=$(git rev-parse HEAD)
  git push --quiet --force origin "HEAD:refs/heads/$branch"
  follow "$branch" "$commit"
}

# Starts ci.yml on BRANCH, whose head is COMMIT, waits for it, and
# returns its status; sets run and url.
follow() {
  gh workflow run ci.yml --ref "$1"
  run=
  for _ in $(seq 60); do
    run=$(gh run list --workflow ci.yml --branch "$1" --event workflow_dispatch --commit "$2" \
      --json databaseId --jq '.[0].databaseId // empty')
    [ -n "$run" ] && break
    sleep 10
  done
  if [ -z "$run" ]; then
    echo "::error::No run of ci.yml started on $1 for $2"
    exit 1
  fi
  url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$run"
  echo "Proving $2 in $url"
  gh run watch "$run" --exit-status --interval 60 >tmp/pin-proof.txt 2>&1
}

trap 'git push --quiet origin --delete "$branch" || true' EXIT
proof=0
prove || proof=$?
# A move that changes what a runtime holds (a new rv-ruby's gems, say)
# leaves doc/licensing.md and runtime/audited.yml behind the runtimes
# CI built; when that is all that failed, CI's Licensing page job has
# uploaded both as they should be, and the move takes them and is
# proved once more (license-audit.md, "The licensing page").
if [ "$proof" -ne 0 ] &&
  [ "$(gh run view "$run" --json jobs --jq '[.jobs[] | select(.conclusion == "failure") | .name] | join(",")')" = "Licensing page is current" ]; then
  gh run download "$run" --name licensing-page --dir tmp/licensing-page
  cp tmp/licensing-page/licensing.md doc/licensing.md
  cp tmp/licensing-page/audited.yml runtime/audited.yml
  git add doc/licensing.md runtime/audited.yml
  git "${bot[@]}" commit --quiet --amend --no-edit
  echo "Took doc/licensing.md and runtime/audited.yml from $url, and proving again." | tee -a "$summary"
  proof=0
  prove || proof=$?
fi
if [ "$proof" -ne 0 ]; then
  echo "proven=false" >>"$output"
  echo "Red: $url" | tee -a "$summary"
  if [ "$count" -gt 1 ]; then exit "$moving"; fi
  echo "::error::The move of $moved did not pass CI: $url"
  exit 1
fi
echo "proven=true" >>"$output"
echo "Green: $url" | tee -a "$summary"
if [ "$land" != true ]; then
  echo "Proven, and left off trunk as asked."
  exit "$moving"
fi

# Onto trunk: as proven when trunk has not moved since, and rebased
# otherwise. A push another push beat is tried again.
for _ in 1 2 3; do
  git fetch --quiet origin trunk
  if git merge-base --is-ancestor FETCH_HEAD HEAD; then
    if git push --quiet origin HEAD:refs/heads/trunk; then
      echo "landed=$commit" >>"$output"
      echo "Landed $commit on trunk as proven." | tee -a "$summary"
      exit "$moving"
    fi
    continue
  fi
  git reset --quiet --hard "$commit"
  if ! git "${bot[@]}" rebase --quiet FETCH_HEAD; then
    git rebase --abort
    echo "::error::The proven move $commit does not rebase cleanly onto trunk"
    exit 1
  fi
  bundle exec rake licensing
  if [ -n "$(git status --porcelain)" ]; then
    git add --all
    git "${bot[@]}" commit --quiet --amend --no-edit
  fi
  if git push --quiet origin HEAD:refs/heads/trunk; then
    landed=$(git rev-parse HEAD)
    echo "Landed $commit on trunk as $landed, rebased; ci.yml runs on trunk to judge it." | tee -a "$summary"
    if ! follow trunk "$landed"; then
      echo "::error::The move rebased onto trunk as $landed is red with what landed meanwhile: $url"
      exit 1
    fi
    echo "landed=$landed" >>"$output"
    echo "Green on trunk: $url" | tee -a "$summary"
    exit "$moving"
  fi
done
echo "::error::trunk moved under every try to land $commit"
exit 1
