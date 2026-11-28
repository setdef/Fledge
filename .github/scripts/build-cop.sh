#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# build-cop.yml's one step. Asks tasks/build_cop.rb what to do next about the
# oldest red full run on trunk after its newest green one, and does it:
#
#   none    nothing is red: deletes the bisect/* branches left over
#   wait    a run it needs has not finished
#   bisect  pushes the commit to bisect/SHA and starts ci.yml there,
#           once, and only if the commit's ci.yml can be started
#   rerun   runs the failed jobs of the run that blames a commit again
#   revert  reverts the commit on trunk and starts ci.yml on trunk
#   stuck   says why, for a person
#
# BUILD_COP_DRY_RUN=true says what it would do and does nothing. GH_TOKEN
# is the token gh uses. Every push, of a branch, a revert, or a deletion,
# is made with BUILD_COP_PUSH_TOKEN, a token of the GitHub App that may
# push workflow files: the run's own token may not, and GitHub refuses a
# push of a commit whose tree holds a workflow file no branch holds with
# "refusing to allow a GitHub App to create or update workflow" (issue
# 96; releases.md, "The push token"). The checkout keeps no credentials.
set -euo pipefail

dry=${BUILD_COP_DRY_RUN:-false}
output=${GITHUB_OUTPUT:-/dev/null}
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
server=${GITHUB_SERVER_URL:-https://github.com}
repository=${GITHUB_REPOSITORY:-setdef/Fledge}
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

# Pushes to the repository with the App's token, which the step before
# has just minted.
push() {
  : "${BUILD_COP_PUSH_TOKEN:?BUILD_COP_PUSH_TOKEN is not set}"
  git push --quiet "https://x-access-token:${BUILD_COP_PUSH_TOKEN}@${server#https://}/$repository" "$@"
}

# Deletes every bisect/* branch, which only this script writes.
clean() {
  git ls-remote --heads origin 'bisect/*' | while read -r _ ref; do
    push --delete "${ref#refs/heads/}"
  done
}

case "$action" in
none)
  clean
  ;;
wait) ;;
bisect)
  branch=bisect/$commit
  # ci.yml can be run on a branch only where the commit's own copy lists
  # workflow_dispatch, which an older commit's may not; GitHub refuses
  # the dispatch, and the cop's run would go red every half hour. A
  # person judges that commit. Not a pipe into grep -q (see revert).
  workflow=$(git show "$commit:.github/workflows/ci.yml" 2>/dev/null || true)
  if ! grep -q '^  workflow_dispatch:' <<<"$workflow"; then
    echo "::warning::The build cop cannot run ci.yml on $commit: its copy has no workflow_dispatch, so a person judges that commit: $reason"
    exit 0
  fi
  # The branch says the run was asked for. GitHub may list that run only
  # minutes later, and until it does the next call finds no run of the
  # commit and says to bisect it again; dispatching again would run it
  # twice. A branch whose runs were all cancelled, by a person or by
  # the next dispatch, asks again.
  if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    any=$(gh run list --workflow ci.yml --branch "$branch" --event workflow_dispatch --json databaseId --jq length)
    if [ "${any:-0}" = 0 ]; then
      echo "The run of ci.yml on $branch is not listed yet; not starting it again." | tee -a "$summary"
      exit 0
    fi
    push --delete "$branch"
  fi
  push "$commit:refs/heads/$branch"
  # A branch with no run to come would make every later call wait.
  if ! gh workflow run ci.yml --ref "$branch"; then
    push --delete "$branch"
    echo "::error::GitHub did not start ci.yml on $branch"
    exit 1
  fi
  # The next call reads the run as waiting only once GitHub lists it.
  started=
  for _ in $(seq "${BUILD_COP_LIST_TRIES:-30}"); do
    started=$(gh run list --workflow ci.yml --branch "$branch" --event workflow_dispatch --json databaseId,conclusion --jq '[.[] | select(.conclusion != "cancelled") | .databaseId] | first // empty')
    [ -n "$started" ] && break
    sleep "${BUILD_COP_LIST_PAUSE:-10}"
  done
  echo "Started ${started:-a run} of ci.yml on $branch." | tee -a "$summary"
  ;;
rerun)
  # GitHub refuses a run with no failed job, or one already running
  # again: the next call reads the runs as they are.
  gh run rerun "$run" --failed || echo "::warning::GitHub would not run the failed jobs of run $run again: $reason"
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
  # Off until a person has seen tasks/build_cop.rb run the parent
  # of a suspect, and stop where it fails too, as a rate limit of Maven
  # Central's makes it (releases.md, "The build cop").
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

The build cop found that it turned trunk's full run red: $reason. Land it again
with the fix.

Provenance: requested
EOF
    if push HEAD:refs/heads/trunk; then
      reverted=$(git rev-parse HEAD)
      echo "Reverted $commit on trunk as $reverted." | tee -a "$summary"
      # The push starts the usual run on trunk, which the next push
      # replaces while it waits; the revert's full run is started by
      # hand too, in a group of its own on trunk.
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
