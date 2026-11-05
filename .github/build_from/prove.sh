#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Experiment only (experiment/build-from). Usage:
#   prove.sh PLATFORM BUILDER_ARCHIVE GAME_FOLDER
#
# On a computer that never ran fledge build, with no Ruby: unpacks the
# builder app into a folder whose name has spaces and characters outside
# ASCII, has it run its own fledge build --from on a copy of the game
# beside it, with no Ruby on PATH and a hostile Ruby environment, and
# runs the app that comes out. PATH holds only the system tools fledge
# runs: tar and gzip, and codesign on macOS.
set -eu
platform=$1
archive=$2
game=$3
work="${RUNNER_TEMP:-/tmp}/build-from proof"
place="$work/Mein Ort/Prüfung 日本"
tools="$work/tools"
rm -rf "$work"
mkdir -p "$place" "$tools"
for tool in tar gzip codesign plutil; do
  found=$(command -v "$tool" || true)
  if [ -n "$found" ]; then ln -s "$found" "$tools/$tool"; fi
done
ls -l "$tools"
tar -xzf "$archive" -C "$place"
cp -R "$game" "$place/Mein Spiel"
cd "$place"
hostile() { env -i HOME="$place" PATH="$tools" RUBYOPT=-rbogus RUBYLIB=/nope GEM_HOME=/nope GEM_PATH=/nope "$@"; }
if hostile /bin/sh -c 'command -v ruby'; then
  echo "ruby is reachable" >&2
  exit 1
fi

echo "== fledge build --from, run by the builder app, inside itself"
hostile "./Builder-$platform/Builder" "Mein Spiel" "Ausgabe"
ls -la Ausgabe
du -sh "Builder-$platform" "Ausgabe/Spiel-$platform"
head -3 "Ausgabe/Spiel-$platform/fledge.cfg"
ls -a "Ausgabe/Spiel-$platform/app"
if [ -e "Ausgabe/Spiel-$platform/Builder" ]; then
  echo "the builder's program came along" >&2
  exit 1
fi

echo "== the app it wrote, unpacked from its archive and run"
mkdir -p "Entpackt"
tar -xzf "Ausgabe/Spiel-$platform.tar.gz" -C "Entpackt"
out=$(hostile "./Entpackt/Spiel-$platform/Spiel")
echo "$out"
expected="Spiel says hello from app: an asset beside the game
RUBYOPT=-rbundler/setup -rbogus"
if [ "$out" != "$expected" ]; then
  echo "expected: $expected" >&2
  exit 1
fi
if [ "$(uname)" = Darwin ]; then
  codesign -dv "Entpackt/Spiel-$platform/Spiel" 2>&1 | grep -E 'Identifier|Signature'
fi
echo "proved on $platform"
