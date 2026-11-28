#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# cut.yml's record on trunk of a release made off it.
#
#   .github/scripts/release-record.sh VERSION COMMIT PIN
#
# VERSION was released from COMMIT, as the pin commit PIN. On trunk as
# it stands, it writes VERSION wherever a release names it, moves the
# entries that were unreleased at COMMIT under VERSION in CHANGELOG.md,
# leaving those that landed since, takes PIN's lib/fledge/SHA256SUMS,
# regenerates docs/reference/licensing.md, and pushes that one commit to trunk,
# with a run of ci.yml started there, since a push made with the
# workflow's token starts none. A push another push beat is tried again
# on the new trunk.
#
# RELEASE_RECORD_DRY_RUN=true commits the record in the checkout and
# stops, pushing and starting nothing; with RELEASE_RECORD_ONTO=SHA, it
# records onto that commit in place of trunk, and fetches nothing.
# GH_TOKEN is the token gh uses.
set -euo pipefail

version=$1
commit=$2
pin=$3
dry=${RELEASE_RECORD_DRY_RUN:-false}
onto=${RELEASE_RECORD_ONTO:-}
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
bot=(-c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com")

mkdir -p tmp
if [ -z "$onto" ]; then git fetch --quiet origin "+refs/tags/v$version:refs/tags/v$version"; fi
git show "$commit:CHANGELOG.md" >tmp/released-changelog.md
for _ in 1 2 3; do
  if [ -n "$onto" ]; then git checkout --quiet --detach "$onto"; else
    git fetch --quiet origin trunk
    git checkout --quiet --detach FETCH_HEAD
  fi
  ruby tasks/release_commit.rb write "$version" --released tmp/released-changelog.md
  git show "$pin:lib/fledge/SHA256SUMS" >lib/fledge/SHA256SUMS
  bundle exec rake licensing
  git add --all
  git "${bot[@]}" commit --quiet --file - <<EOF
chore: record $version on trunk

$version was released off trunk from $commit, as the tag v$version on
$pin. Trunk now names its version and its pins, and its CHANGELOG has
under it the entries that were released.

Provenance: requested
EOF
  git log -1 --stat --format='%h %s' | cat
  if [ "$dry" = true ]; then
    echo "Dry run: would push $(git rev-parse HEAD) to trunk"
    exit 0
  fi
  if git push --quiet origin HEAD:refs/heads/trunk; then
    gh workflow run ci.yml --ref trunk
    echo "Recorded v$version on trunk as $(git rev-parse HEAD)." | tee -a "$summary"
    exit 0
  fi
done
echo "::error::trunk moved under every try to record v$version"
exit 1
