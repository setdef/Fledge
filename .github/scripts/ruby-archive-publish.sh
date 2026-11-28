#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Publishes Fledge's own Ruby archives for glibc Linux, as
# .github/scripts/ruby-archive.sh builds them, on a pre-release of this
# repository, so that a runtime's pin can name them by URL and SHA-256 as
# it names an upstream input ("Rolling upstream inputs").
#
#   .github/scripts/ruby-archive-publish.sh FOLDER
#
# FOLDER holds ruby-VERSION-x86_64-linux.tar.gz and
# ruby-VERSION-aarch64-linux.tar.gz, of one VERSION, and nothing else
# named ruby-*. The pre-release is named
# inputs-fledge-ruby-VERSION-YYYYMMDD-COMMIT: what the archives are, the
# day they were published, in UTC, and the commit whose recipe built
# them, which is also the commit the tag names. A pre-release of that
# name that exists already is never overwritten: the run fails.
#
# With DRY_RUN=1 it checks the archives and prints the name and the
# notes it would publish, and needs neither gh nor the network. Else it
# creates the pre-release with gh, which must be logged in to this
# repository, then downloads each archive back from it and checks its
# SHA-256. COMMIT is HEAD's unless FLEDGE_COMMIT names one, and
# FLEDGE_RUN_URL, when set, names the run that built them in the notes.

set -euo pipefail

folder=${1:?usage: ruby-archive-publish.sh FOLDER}
platforms=(x86_64-linux aarch64-linux)

shopt -s nullglob
found=("$folder"/ruby-*.tar.gz)
shopt -u nullglob
if [ "${#found[@]}" -ne "${#platforms[@]}" ]; then
  echo "ruby-archive-publish.sh: $folder holds ${#found[@]} archives, not one for each of ${platforms[*]}" >&2
  exit 1
fi
first=$(basename "${found[0]}")
version=${first#ruby-}
version=${version%-*-linux.tar.gz}
assets=()
for platform in "${platforms[@]}"; do
  asset=$folder/ruby-$version-$platform.tar.gz
  if [ ! -f "$asset" ]; then
    echo "ruby-archive-publish.sh: no ruby-$version-$platform.tar.gz in $folder" >&2
    exit 1
  fi
  assets+=("$asset")
done

commit=${FLEDGE_COMMIT:-$(git rev-parse HEAD)}
tag=inputs-fledge-ruby-$version-$(date -u +%Y%m%d)-${commit:0:10}
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
{
  echo "Fledge's own build of Ruby $version for glibc Linux, from the recipe at $commit"
  echo "(.github/scripts/ruby-archive.sh and tasks/ruby_archive.rb): built in Ubuntu 22.04,"
  echo "so it runs on glibc 2.35 or later, with YJIT and ZJIT."
  if [ -n "${FLEDGE_RUN_URL:-}" ]; then echo "Built by $FLEDGE_RUN_URL."; fi
  echo
  echo "Not a version of Fledge. Kept for runtime/sources.yml to pin by URL and SHA-256."
  echo
  echo '```'
  for asset in "${assets[@]}"; do
    echo "$(sha256sum "$asset" | cut -d' ' -f1)  $(basename "$asset")"
  done
  echo '```'
} >"$notes"

echo "pre-release: $tag"
cat "$notes"
if [ -n "${DRY_RUN:-}" ]; then
  echo "dry run: nothing published"
  exit 0
fi

if gh release view "$tag" >/dev/null 2>&1; then
  echo "ruby-archive-publish.sh: $tag exists, and is never overwritten" >&2
  exit 1
fi
gh release create "$tag" --prerelease --latest=false --target "$commit" --title "$tag" --notes-file "$notes" "${assets[@]}"

back=$(mktemp -d)
gh release download "$tag" --dir "$back" --pattern 'ruby-*.tar.gz'
for asset in "${assets[@]}"; do
  echo "$(sha256sum "$asset" | cut -d' ' -f1)  $back/$(basename "$asset")"
done | sha256sum --strict -c -
rm -rf "$back"
