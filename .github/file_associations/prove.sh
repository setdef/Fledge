#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Experiment only (experiment/file-associations). Usage:
#   prove.sh PLATFORM BUILDER_ARCHIVE GAME_FOLDER
#
# On a computer that never ran fledge build, with no Ruby and no Fledge
# runtime anywhere: unpacks the builder app, built with build_tools:
# true, into a folder whose name has spaces and characters outside
# ASCII, has it run its own fledge build --from on a copy of a windowed
# game beside it, in a hostile Ruby environment, and runs the app and
# the installers that come out. PATH holds only the system tools fledge
# runs: tar and gzip; codesign, plutil, ditto, and hdiutil on macOS;
# mksquashfs and dpkg-deb on Linux, where the system has them.
set -eu
platform=$1
archive=$2
game=$3
work="${RUNNER_TEMP:-/tmp}/file-associations proof"
place="$work/Mein Ort/Prüfung 日本"
tools="$work/tools"
rm -rf "$work"
mkdir -p "$place" "$tools" "$work/cache"
for tool in tar gzip codesign plutil ditto hdiutil mksquashfs dpkg-deb; do
  found=$(command -v "$tool" || true)
  if [ -n "$found" ]; then ln -s "$found" "$tools/$tool"; fi
done
ls -l "$tools"
tar -xzf "$archive" -C "$place"
cp -R "$game" "$place/Mein Spiel"
cd "$place"
builder="Builder-$platform"
hostile() { env -i HOME="$place" PATH="$tools" XDG_CACHE_HOME="$work/cache" RUBYOPT=-rbogus RUBYLIB=/nope GEM_HOME=/nope GEM_PATH=/nope "$@"; }
if hostile /bin/sh -c 'command -v ruby'; then
  echo "ruby is reachable" >&2
  exit 1
fi
if [ -d "$builder/tools" ]; then
  echo "== the builder's tools folder: $(du -sk "$builder/tools" | cut -f1) KB of $(du -sk "$builder" | cut -f1) KB"
  ls -la "$builder/tools"
else
  echo "== the builder carries no tools folder"
fi

echo "== fledge build --from, run by the builder app, inside itself, with no runtime at hand"
hostile "./$builder/Builder" "Mein Spiel" "Ausgabe"
ls -la Ausgabe
for leftover in "Ausgabe/Spiel-$platform/tools" "Ausgabe/Spiel-$platform/Spiel.app/Contents/Resources/tools"; do
  if [ -e "$leftover" ]; then
    echo "the builder's tools came along into $leftover" >&2
    exit 1
  fi
done

echo "== the app it wrote, unpacked from its archive and run with a path, as an opened file gives one"
mkdir -p Entpackt
tar -xzf "Ausgabe/Spiel-$platform.tar.gz" -C Entpackt
report="$work/report.txt"
case "$platform" in
  *darwin)
    bundle="Entpackt/Spiel-$platform/Spiel.app"
    codesign --verify --deep --strict --verbose=2 "$bundle"
    plutil -extract CFBundleDocumentTypes.0.LSItemContentTypes.0 raw "$bundle/Contents/Info.plist"
    program="$bundle/Contents/MacOS/Spiel"
    hdiutil imageinfo "Ausgabe/Spiel-$platform.dmg" | grep -E '^Format:'
    ;;
  *)
    program="Entpackt/Spiel-$platform/Spiel"
    grep -E '^(Exec|MimeType)=' "Entpackt/Spiel-$platform/com.example.Spiel.desktop"
    appimage="Ausgabe/Spiel-$platform.AppImage"
    hostile APPIMAGE_EXTRACT_AND_RUN=1 TMPDIR="$work" "./$appimage" "$work/from-appimage.txt"
    cat "$work/from-appimage.txt"
    if [ -e "Ausgabe/Spiel-$platform.deb" ]; then dpkg-deb --info "Ausgabe/Spiel-$platform.deb" | grep -E 'Package|Architecture'; fi
    ;;
esac
hostile "./$program" "$report"
out=$(cat "$report")
echo "$out"
if [ "$out" != "Spiel says hello from app: an asset beside the game" ]; then
  echo "unexpected report" >&2
  exit 1
fi
echo "proved on $platform"
