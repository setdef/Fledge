#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Fails if anything a Windows Build job is about to upload holds a DLL
# of Microsoft's Visual C++ runtime. The rule is that
# nothing setdef publishes carries it, an app that Fledge's CI builds
# and uploads included (doc/contributors/decisions.md, 2026-11-21), and a public
# repository's artifacts are anyone's to download.
#
#   check-no-visual-c-runtime.sh FOLDER...
#
# Every file under each FOLDER is read: one named vcruntime* or msvcp*
# fails, and so does one inside a .zip or an .msix, which are zip
# archives, listed with Windows' own tar (libarchive's). A setup
# program's NSIS archive is one no tool on the runner lists, so each
# "NAME-setup.exe" must have the "NAME.zip" beside it, which holds the
# same app's files and is read here.
#
# A Build job's folders hold tens of thousands of files, and Windows
# takes milliseconds to start each program, so one grep reads every
# name from find's listing, and only an archive costs a program of its
# own.

set -eu

fail() {
  echo "::error::$*" >&2
  exit 1
}

pattern='(^|[/\\])(vcruntime|msvcp)[^/\\]*$'
bsdtar="$(cygpath -u "$SYSTEMROOT")/System32/tar.exe"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for folder in "$@"; do
  [ ! -d "$folder" ] || find "$folder" -type f
done >"$work/files"
if grep -Ei "$pattern" "$work/files" >&2; then
  fail "the files above are of Microsoft's Visual C++ runtime, which CI must not upload"
fi
grep -Ei '\.(zip|msix)$' "$work/files" >"$work/archives" || true
while IFS= read -r file; do
  "$bsdtar" -tf "$(cygpath -w "$file")" >"$work/listing" || fail "could not list $file"
  if grep -Ei "$pattern" "$work/listing" >&2; then
    fail "$file holds Microsoft's Visual C++ runtime (above), which CI must not upload"
  fi
done <"$work/archives"
grep -- '-setup\.exe$' "$work/files" >"$work/setups" || true
while IFS= read -r file; do
  [ -f "${file%-setup.exe}.zip" ] || fail "$file has no ${file%-setup.exe}.zip beside it to read its app from"
done <"$work/setups"
echo "ok: none of Microsoft's Visual C++ runtime in $(wc -l <"$work/files") files, $(wc -l <"$work/archives") of them archives read through"
