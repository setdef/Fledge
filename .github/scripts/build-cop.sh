#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# build-cop.yml's one step (doc/contributors/design/releases.md, "The
# build cop"). Asks tasks/build_cop.rb what to do next about the oldest
# red full run on trunk after its newest green one, and does it:
#
#   none    nothing is red: deletes the bisect/* branches left over
#   wait    a run it needs has not finished
#   bisect  pushes the commit to bisect/SHA and starts ci.yml there
#   rerun   runs the failed jobs of the run that blames a commit again
#   revert  reverts the commit on trunk and starts ci.yml on trunk
#   stuck   says why, for a person
#
# BUILD_COP_DRY_RUN=true says what it would do and does nothing. GH_TOKEN
# is the token gh uses; git pushes with the checkout's credentials.
set -euo pipefail

dry=${BUILD_COP_DRY_RUN:-false}
output=${GITHUB_OUTPUT:-/dev/null}
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
bot=(-c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com")

mkdir -p tmp
git fetch --quiet origin trunk
git rev-list --first-parent --max-count=300 FETCH_HEAD >tmp/build-cop-commits.txt
ruby tasks/build_cop.rb tmp/build-cop-commits.txt >tmp/build-cop.txt
cat tmp/build-cop.txt >>"$output"
field() { sed -n "s/^$1=//p" tmp/build-cop.txt; }
action=$(field action)
commit=$(field commit)
run=$(field run)
reason=$(field reason)
echo "${action}${commit:+ $commit}: $reason" | tee -a "$summary"
if [ "$dry" = true ]; then
  echo "Dry run: did nothing."
  exit 0
fi

# Deletes every bisect/* branch, which only this script writes.
clean() {
  git ls-remote --heads origin 'bisect/*' | while read -r _ ref; do
    git push --quiet origin --delete "${ref#refs/heads/}"
  done
}

case "$action" in
none)
  clean
  ;;
wait) ;;
bisect)
  branch=bisect/$commit
  git push --quiet origin "$commit:refs/heads/$branch"
  gh workflow run ci.yml --ref "$branch"
  # The next call reads the run as waiting only once GitHub lists it.
  for _ in $(seq 30); do
    started=$(gh run list --workflow ci.yml --branch "$branch" --event workflow_dispatch --json databaseId --jq '.[0].databaseId // empty')
    [ -n "$started" ] && break
    sleep 10
  done
  echo "Started ${started:-a run} of ci.yml on $branch." | tee -a "$summary"
  ;;
rerun)
  gh run rerun "$run" --failed
  ;;
revert)
  # Not a pipe into grep -q: with pipefail, grep leaving early makes git
  # log die of SIGPIPE, and the test then says "not reverted".
  already=$(git log -1 --format=%H --grep="^This reverts commit $commit" FETCH_HEAD)
  if [ -n "$already" ]; then
    echo "$commit is reverted on trunk already as $already; trunk's next green run ends this." | tee -a "$summary"
    exit 0
  fi
  subject=$(git log -1 --format=%s "$commit")
  # A release's commits are tagged and published, and a revert of the
  # cop's own revert would undo its work: a person decides those.
  case "$subject" in
  "chore: release "* | "chore: pin "* | "chore: record "* | "revert: "* | "Revert \""*)
    echo "::warning::The build cop would revert $commit ($subject), which is a person's to revert: $reason"
    exit 0
    ;;
  esac
  # Off until a failure that outlasts one rerun, as a rate limit of Maven
  # Central's may, cannot blame the batch's oldest commit (releases.md,
  # "The build cop").
  if [ "${BUILD_COP_REVERT:-false}" != true ]; then
    echo "::warning::The build cop would revert $commit ($subject); BUILD_COP_REVERT is not true: $reason"
    exit 0
  fi
  for _ in 1 2 3; do
    git fetch --quiet origin trunk
    git checkout --quiet --detach FETCH_HEAD
    if ! git "${bot[@]}" revert --no-edit --no-commit "$commit"; then
      git revert --abort || true
      echo "::error::$commit does not revert cleanly on trunk: $reason"
      exit 1
    fi
    git "${bot[@]}" commit --quiet --file - <<EOF
revert: ${subject}

This reverts commit $commit.

The build cop found that it turned trunk's full run red: $reason
(doc/contributors/design/releases.md, "The build cop"). Land it again
with the fix.

Provenance: requested
EOF
    if git push --quiet origin HEAD:refs/heads/trunk; then
      reverted=$(git rev-parse HEAD)
      echo "Reverted $commit on trunk as $reverted." | tee -a "$summary"
      # A push with this workflow's token starts no run, so the revert's
      # full run is started by hand, in a group of its own on trunk.
      gh workflow run ci.yml --ref trunk
      clean
      exit 0
    fi
  done
  echo "::error::trunk moved under every try to revert $commit"
  exit 1
  ;;
stuck)
  echo "::warning::The build cop cannot go on: $reason"
  ;;
*)
  echo "::error::tasks/build_cop.rb said nothing it knows: $action"
  exit 1
  ;;
esac
