#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# cut.yml's release of a commit CI has proven, with nobody in it
# (doc/contributors/design/releases.md, "How a release is made").
#
#   .github/scripts/release-cut.sh COMMIT
#
# On COMMIT, which must have a run of ci.yml that passed on every job, it
# writes the release commit (tasks/release_commit.rb, the version by
# releases.md's rule, and rake licensing) and pushes it to the branch
# release-next, which only this script writes. It starts a full run of
# ci.yml there, and installed.yml on COMMIT against the last release,
# and waits for both. Green, it writes the pin commit from the release
# commit's run (rake runtime:pin), pushes it to the branch, starts and
# waits for its short run, tags it, and starts release.yml on the tag
# with publish, and waits for that, writing version and pin to GITHUB_OUTPUT
# for release-record.sh. The branch is deleted at the end. Nothing is
# pushed to trunk.
#
# RELEASE_CUT_STOP=local writes the release commit in the checkout and
# stops, fetching, pushing, and starting nothing. RELEASE_CUT_STOP=tag
# runs both commits' CI on the branch and stops before the tag,
# publishing nothing. GH_TOKEN is the token gh uses.
set -euo pipefail

commit=$1
stop=${RELEASE_CUT_STOP:-}
branch="release-next"
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
server=${GITHUB_SERVER_URL:-https://github.com}
repository=${GITHUB_REPOSITORY:-setdef/Fledge}
bot=(-c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com")

say() { echo "$*" | tee -a "$summary"; }

git checkout --quiet --detach "$commit"
if [ "$stop" != local ]; then
  run=$(ruby tasks/ci_runs.rb green "$commit" --every-job)
  say "Releasing $commit, proven by $server/$repository/actions/runs/$run."
fi
last=$(ruby -e 'print File.read("lib/fledge/version.rb")[/VERSION = "(.+)"/, 1]')
version=$(ruby tasks/release_commit.rb next)
if [ "$stop" != local ]; then git fetch --quiet --tags origin; fi
if git rev-parse --quiet --verify "refs/tags/v$version" >/dev/null; then
  echo "::error::v$version is tagged already"
  exit 1
fi
mkdir -p tmp
cp CHANGELOG.md tmp/released-changelog.md
ruby tasks/release_commit.rb write "$version"
bundle exec rake licensing
git add --all
git "${bot[@]}" commit --quiet --file - <<EOF
chore: release $version

Released with nobody in the loop from $commit, whose CI passed on
every job, by cut.yml (doc/contributors/design/releases.md, "How a
release is made").

Provenance: requested
EOF
release=$(git rev-parse HEAD)
git log -1 --stat --format='%h %s' | cat
if [ "$stop" = local ]; then
  say "Stopped as asked: would release $version, after $last, from $release on $commit."
  exit 0
fi

# Starts WORKFLOW on the branch, whose head is COMMIT, with the inputs
# after them, and sets run to the run it started.
start() {
  local workflow=$1 head=$2
  shift 2
  gh workflow run "$workflow" --ref "$branch" "$@"
  run=
  for _ in $(seq 60); do
    run=$(gh run list --workflow "$workflow" --branch "$branch" --event workflow_dispatch --commit "$head" \
      --json databaseId --jq '.[0].databaseId // empty')
    [ -n "$run" ] && break
    sleep 10
  done
  if [ -z "$run" ]; then
    echo "::error::No run of $workflow started on $branch for $head"
    exit 1
  fi
}

# Waits for run RUN, and fails naming WHAT and the run unless it passed.
wait_for() {
  if ! gh run watch "$1" --exit-status --interval 60 >"tmp/release-cut-$1.txt" 2>&1; then
    say "Red: $2, $server/$repository/actions/runs/$1"
    echo "::error::$2 did not pass: $server/$repository/actions/runs/$1"
    exit 1
  fi
  say "Green: $2, $server/$repository/actions/runs/$1"
}

trap 'git push --quiet origin --delete "$branch" || true' EXIT
git push --quiet --force origin "HEAD:refs/heads/$branch"
start ci.yml "$release"
ci=$run
start installed.yml "$release" -f tag="v$last" -f commit="$commit"
installed=$run
wait_for "$ci" "the release commit's CI"
wait_for "$installed" "installed.yml on $commit"

bundle exec rake runtime:pin
git "${bot[@]}" commit --quiet --file - lib/fledge/SHA256SUMS <<EOF
chore: pin $version's runtimes

The runtimes $server/$repository/actions/runs/$ci built from the
release commit.

Provenance: requested
EOF
pin=$(git rev-parse HEAD)
git push --quiet --force origin "HEAD:refs/heads/$branch"
start ci.yml "$pin"
wait_for "$run" "the pin commit's short CI"
if [ "$stop" = tag ]; then
  say "Stopped as asked before the tag: v$version would go on $pin."
  exit 0
fi

git "${bot[@]}" tag --annotate "v$version" --message "Fledge $version" "$pin"
git push --quiet origin "refs/tags/v$version"
gh workflow run release.yml --ref "v$version" -f tag="v$version" -f publish=true
run=
for _ in $(seq 60); do
  run=$(gh run list --workflow release.yml --event workflow_dispatch --commit "$pin" --json databaseId --jq '.[0].databaseId // empty')
  [ -n "$run" ] && break
  sleep 10
done
if [ -z "$run" ]; then
  echo "::error::No run of release.yml started for v$version"
  exit 1
fi
wait_for "$run" "release.yml on v$version"

echo "version=$version" >>"${GITHUB_OUTPUT:-/dev/null}"
echo "pin=$pin" >>"${GITHUB_OUTPUT:-/dev/null}"
say "Released v$version from $pin."
