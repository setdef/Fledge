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
# check LABEL ACTUAL EXPECTED
check() {
  [ "$2" = "$3" ] || { echo "$1 is '$2', not '$3'" >&2; exit 1; }
  echo "ok: $1 is $3"
}
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
    plist="$bundle/Contents/Info.plist"
    check "the folders' content type" "$(plutil -extract CFBundleDocumentTypes.0.LSItemContentTypes.0 raw "$plist")" public.folder
    check "the levels' extension" "$(plutil -extract CFBundleDocumentTypes.1.CFBundleTypeExtensions.0 raw "$plist")" spiellevel
    check CFBundleVersion "$(plutil -extract CFBundleVersion raw "$plist")" 2.3.417
    check CFBundleShortVersionString "$(plutil -extract CFBundleShortVersionString raw "$plist")" 2.3.4
    program="$bundle/Contents/MacOS/Spiel"
    hdiutil imageinfo "Ausgabe/Spiel-$platform.dmg" | grep -E '^Format:'
    ;;
  *)
    program="Entpackt/Spiel-$platform/Spiel"
    desktop="Entpackt/Spiel-$platform/com.example.Spiel.desktop"
    check Comment "$(sed -n 's/^Comment=//p' "$desktop")" "Ein Spiel aus einem Ordner"
    check Exec "$(sed -n 's/^Exec=//p' "$desktop")" "Spiel %F"
    check MimeType "$(sed -n 's/^MimeType=//p' "$desktop")" "inode/directory;application/x-spiellevel;"
    appimage="Ausgabe/Spiel-$platform.AppImage"
    hostile APPIMAGE_EXTRACT_AND_RUN=1 TMPDIR="$work" "./$appimage" "$work/from-appimage.txt"
    cat "$work/from-appimage.txt"
    deb="Ausgabe/Spiel-$platform.deb"
    if [ -e "$deb" ]; then
      check "the .deb's Homepage" "$(dpkg-deb --field "$deb" Homepage)" https://example.com/spiel
      check "the .deb's Description" "$(dpkg-deb --field "$deb" Description | head -n 1)" "Ein Spiel aus einem Ordner"
      dpkg-deb --contents "$deb" | grep -q "usr/share/doc/com.example.spiel/copyright$" || { echo "no copyright in the .deb" >&2; exit 1; }
      dpkg-deb --contents "$deb" | grep -q "usr/share/doc/com.example.spiel/changelog.gz$" || { echo "no changelog.gz in the .deb" >&2; exit 1; }
      dpkg-deb --contents "$deb" | grep -q "usr/share/applications/com.example.Spiel.desktop$" || { echo "no desktop entry in the .deb" >&2; exit 1; }
      echo "ok: the .deb holds the license as copyright, the changelog, and the desktop entry"
    fi
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
