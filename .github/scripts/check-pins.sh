#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Checks runtimes against the pins a commit ships (ADR 014): FOLDER must
# hold exactly the release assets Fledge asks for at this checkout's
# Fledge::VERSION (RuntimeBuilder.release_assets), PINS must pin exactly
# those, and each asset must match its pin, as GNU's sha256sum --strict
# -c reads them. release.yml runs it on the runtimes it is about to
# publish, and a pin commit's CI on the runtimes of its parent's run.
#
#   .github/scripts/check-pins.sh FOLDER PINS
set -eu

folder=$1
pins=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ruby -r "$root/tasks/runtime_builder" -e 'puts RuntimeBuilder.release_assets' | LC_ALL=C sort > "$work/expected"
(cd "$folder" && ls) | LC_ALL=C sort > "$work/found"
cut -c67- "$pins" | LC_ALL=C sort > "$work/pinned"

if ! diff "$work/expected" "$work/found"; then
  echo "error: $folder does not hold exactly the release's assets (< missing, > unexpected)" >&2
  exit 1
fi
if ! diff "$work/found" "$work/pinned"; then
  echo "error: $2 does not pin exactly the release's assets (< not pinned, > pinned but absent)" >&2
  exit 1
fi
if ! (cd "$folder" && sha256sum --strict -c "$pins"); then
  echo "error: an asset in $folder does not match its pin in $2" >&2
  exit 1
fi
cat "$work/found"
