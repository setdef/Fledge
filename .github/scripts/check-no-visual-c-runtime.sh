#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Fails if anything a Windows Build job is about to upload holds a DLL
# of Microsoft's Visual C++ runtime. The maintainer's rule is that
# nothing setdef publishes carries it, "not an app that Fledge's CI
# builds and uploads" (doc/contributors/decisions.md), and a public
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

set -eu

fail() {
  echo "::error::$*" >&2
  exit 1
}

pattern='(^|[/\\])(vcruntime|msvcp)[^/\\]*$'
bsdtar="$(cygpath -u "$SYSTEMROOT")/System32/tar.exe"
listing=$(mktemp)
found=$(mktemp)
trap 'rm -f "$listing" "$found"' EXIT
files=0
archives=0
for folder in "$@"; do
  [ -d "$folder" ] || continue
  find "$folder" -type f >"$found"
  while IFS= read -r file; do
    files=$((files + 1))
    if printf '%s\n' "$file" | grep -Eiq "$pattern"; then
      fail "$file is of Microsoft's Visual C++ runtime, which CI must not upload"
    fi
    case $file in
      *.zip | *.msix)
        "$bsdtar" -tf "$(cygpath -w "$file")" >"$listing" || fail "could not list $file"
        archives=$((archives + 1))
        if grep -Ei "$pattern" "$listing" >&2; then
          fail "$file holds Microsoft's Visual C++ runtime (above), which CI must not upload"
        fi
        ;;
      *-setup.exe)
        [ -f "${file%-setup.exe}.zip" ] || fail "$file has no ${file%-setup.exe}.zip beside it to read its app from"
        ;;
    esac
  done <"$found"
done
echo "ok: none of Microsoft's Visual C++ runtime in $files files, $archives of them archives read through"
