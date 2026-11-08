#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of fledge build --from (ADR 032), on a runner that never ran
# fledge build, with no Ruby and no Fledge runtime anywhere: unpacks the
# builder app, built with build_tools: true and Fledge as a gem, into a
# folder whose name has spaces and characters outside ASCII, has it run
# its own fledge build --from on a copy of a windowed game beside it, in
# a hostile Ruby environment, reads the result's identity back with the
# system's own tools, and runs what it wrote. Then it has the builder
# refuse what --from refuses, by exit status and message: a project with
# a Gemfile, an app of another release or platform, and a folder Fledge
# did not build. PATH holds only the system tools fledge runs: tar and
# gzip; codesign, plutil, ditto, and hdiutil on macOS; mksquashfs and
# dpkg-deb on Linux.
#
#   .github/scripts/deliver-from.sh PLATFORM BUILDER_ARCHIVE GAME_FOLDER
set -eu
platform=$1
archive=$2
game=$3
bad_app_status=${FROM_REFUSES_A_BAD_APP_WITH:?the workflow sets this}
work="${RUNNER_TEMP:-/tmp}/from proof"
place="$work/Mein Ort/Prüfung 日本"
tools="$work/tools"
rm -rf "$work"
mkdir -p "$place" "$tools" "$work/cache"
for tool in tar gzip codesign plutil ditto hdiutil mksquashfs dpkg-deb; do
  found=$(command -v "$tool" || true)
  if [ -n "$found" ]; then ln -s "$found" "$tools/$tool"; fi
done
tar -xzf "$archive" -C "$place"
cp -R "$game" "$place/Mein Spiel"
cd "$place"
builder="Builder-$platform"
# check LABEL ACTUAL EXPECTED
check() {
  [ "$2" = "$3" ] || {
    echo "$1 is '$2', not '$3'" >&2
    exit 1
  }
  echo "ok: $1 is $3"
}
hostile() { env -i HOME="$place" PATH="$tools" XDG_CACHE_HOME="$work/cache" RUBYOPT=-rbogus RUBYLIB=/nope GEM_HOME=/nope GEM_PATH=/nope "$@"; }
if hostile /bin/sh -c 'command -v ruby'; then
  echo "ruby is reachable" >&2
  exit 1
fi

echo "== fledge build --from, run by the builder app, inside itself, with no runtime at hand"
hostile "./$builder/Builder" "Mein Spiel" Ausgabe
ls -la Ausgabe
for leftover in "Ausgabe/Spiel-$platform/tools" "Ausgabe/Spiel-$platform/Spiel.app/Contents/Resources/tools"; do
  if [ -e "$leftover" ]; then
    echo "the builder's tools came along into $leftover" >&2
    exit 1
  fi
done

echo "== the app it wrote, unpacked from its archive, its identity read back, and run with a path"
mkdir -p Entpackt
tar -xzf "Ausgabe/Spiel-$platform.tar.gz" -C Entpackt
report="$work/report.txt"
case "$platform" in
  *darwin)
    bundle="Entpackt/Spiel-$platform/Spiel.app"
    codesign --verify --deep --strict --verbose=2 "$bundle"
    plist="$bundle/Contents/Info.plist"
    check CFBundleIdentifier "$(plutil -extract CFBundleIdentifier raw "$plist")" com.example.Spiel
    check CFBundleVersion "$(plutil -extract CFBundleVersion raw "$plist")" 2.3.417
    check CFBundleShortVersionString "$(plutil -extract CFBundleShortVersionString raw "$plist")" 2.3.4
    check "the folders' content type" "$(plutil -extract CFBundleDocumentTypes.0.LSItemContentTypes.0 raw "$plist")" public.folder
    check "the levels' extension" "$(plutil -extract CFBundleDocumentTypes.1.CFBundleTypeExtensions.0 raw "$plist")" spiellevel
    program="$bundle/Contents/MacOS/Spiel"
    hdiutil imageinfo "Ausgabe/Spiel-$platform.dmg" | grep -E '^Format:'
    ;;
  *)
    program="Entpackt/Spiel-$platform/Spiel"
    desktop="Entpackt/Spiel-$platform/com.example.Spiel.desktop"
    check Comment "$(sed -n 's/^Comment=//p' "$desktop")" "Ein Spiel aus einem Ordner"
    check Exec "$(sed -n 's/^Exec=//p' "$desktop")" "Spiel %F"
    check MimeType "$(sed -n 's/^MimeType=//p' "$desktop")" "inode/directory;application/x-spiellevel;"
    hostile APPIMAGE_EXTRACT_AND_RUN=1 TMPDIR="$work" "./Ausgabe/Spiel-$platform.AppImage" "$work/from-appimage.txt"
    check "what the AppImage wrote" "$(cat "$work/from-appimage.txt")" "Spiel says hello from app: an asset beside the game"
    deb="Ausgabe/Spiel-$platform.deb"
    check "the .deb's Homepage" "$(dpkg-deb --field "$deb" Homepage)" https://example.com/spiel
    check "the .deb's Description" "$(dpkg-deb --field "$deb" Description | head -n 1)" "Ein Spiel aus einem Ordner"
    dpkg-deb --contents "$deb" | grep -q "usr/share/applications/com.example.Spiel.desktop$"
    dpkg-deb --contents "$deb" | grep -q "usr/share/doc/com.example.spiel/changelog.gz$"
    echo "ok: the .deb holds the desktop entry and the changelog"
    ;;
esac
hostile "./$program" "$report"
check "what the app wrote" "$(cat "$report")" "Spiel says hello from app: an asset beside the game"

# refused LABEL STATUS MESSAGE PROJECT [APP]: the builder, given these,
# exits with STATUS, says MESSAGE, and writes nothing. The message tells
# a refusal from a Ruby that crashed with the same status.
refused() {
  label=$1
  want=$2
  message=$3
  shift 3
  status=0
  output=$(hostile "./$builder/Builder" "$1" Abgewiesen ${2+"$2"} 2>&1) || status=$?
  echo "$output"
  check "$label's exit status" "$status" "$want"
  case "$output" in
    *"$message"*) echo "ok: $label says: $message" ;;
    *)
      echo "$label does not say: $message" >&2
      exit 1
      ;;
  esac
  if [ -e Abgewiesen ]; then
    echo "$label wrote Abgewiesen" >&2
    exit 1
  fi
}

# rewrite FOLDER RELEASE PLATFORM: a copy of the builder, as an app that
# RELEASE built for PLATFORM says it is in fledge.cfg's first line.
rewrite() {
  cp -R "$builder" "$1"
  sed "1s/^# Written by fledge build [^ ]* for [^:]*:/# Written by fledge build $2 for $3:/" "$1/fledge.cfg" > "$1/fledge.cfg.new"
  mv "$1/fledge.cfg.new" "$1/fledge.cfg"
}

echo "== what --from refuses"
cp -R "$game" "Mit Gemfile"
echo 'source "https://rubygems.org"' > "Mit Gemfile/Gemfile"
refused "a project with a Gemfile" 1 "--from builds no gems" "Mit Gemfile"

current=$(sed -n '1s/^# Written by fledge build \([^ ]*\) for .*/\1/p' "$builder/fledge.cfg")
rewrite "Andere Version" 0.0.1 "$platform"
refused "an app of another release" "$bad_app_status" "was built by Fledge 0.0.1" "Mein Spiel" "Andere Version"

case "$platform" in
  *darwin) other=x86_64-linux ;;
  *) other=arm64-darwin ;;
esac
rewrite "Andere Plattform" "$current" "$other"
refused "an app for another platform" "$bad_app_status" "is an app for $other" "Mein Spiel" "Andere Plattform"

mkdir "Kein Fledge"
echo "not an app" > "Kein Fledge/Spiel"
refused "a folder Fledge did not build" "$bad_app_status" "is not an app fledge build wrote" "Mein Spiel" "Kein Fledge"

echo "proved on $platform"
