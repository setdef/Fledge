#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of examples/markdown_preview on macOS and Linux: unpacks
# "Markdown Preview-PLATFORM.tar.gz", runs its console program, md2html,
# on a Markdown file and compares the HTML it prints with what kramdown
# prints under bundle exec (EXPECTED, a file the Build job wrote), checks
# that the app declares Markdown files to the system (the bundle's
# CFBundleDocumentTypes, the desktop entry's MimeType), and opens the
# file with its windowed program as each system's file manager does:
# on macOS with open -a, through Launch Services, and on Linux with the
# file's path, as the desktop entry's Exec with %F replaced gives it,
# with BROWSER naming a recorder, which must be handed the preview page.
#
#   deliver-markdown.sh ARCHIVE SAMPLE EXPECTED
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

archive=$1
sample=$2
expected=$3
name="Markdown Preview"

fail() {
  echo "::error::Delivery (markdown_preview): $*" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
place="$work/My Apps/Ünïcödé 日本"
mkdir -p "$place" "$work/tmp" "$work/empty-path"
tar -xzf "$archive" -C "$place"
root="$place/$(basename "$archive" .tar.gz)"
cp "$sample" "$work/notes.md"

# md2html, from / in an empty environment, prints kramdown's HTML.
status=0
(cd / && env -i PATH="$work/empty-path" HOME="$work" "$root/md2html" "$work/notes.md") >"$work/out.html" 2>"$work/err" || status=$?
[ "$status" -eq 0 ] || { cat "$work/err"; fail "md2html exited with $status"; }
[ ! -s "$work/err" ] || { cat "$work/err"; fail "md2html wrote to standard error"; }
cmp -s "$work/out.html" "$expected" || { diff "$expected" "$work/out.html" || true; fail "md2html printed other HTML than bundle exec"; }
echo "ok: md2html prints what bundle exec prints"

# A file it cannot read, and an option it does not know, end it with
# sysexits.h's EX_NOINPUT and EX_USAGE, and a line that says why.
for case in "66 No such file or directory $work/missing.md" "64 unknown option --nope"; do
  want=${case%% *}
  argument=${case##* }
  status=0
  (cd / && env -i PATH="$work/empty-path" HOME="$work" "$root/md2html" "$argument") >/dev/null 2>"$work/err" || status=$?
  [ "$status" -eq "$want" ] || { cat "$work/err"; fail "md2html $argument exited with $status, not $want"; }
  reason=${case#* }
  reason=${reason% *}
  grep -qF "$reason" "$work/err" || { cat "$work/err"; fail "md2html $argument did not say: $reason"; }
done
echo "ok: md2html exits 66 on a file it cannot read and 64 on an unknown option"

case "$(uname -s)" in
  Darwin)
    plist="$root/$name.app/Contents/Info.plist"
    types=CFBundleDocumentTypes.0
    [ "$(plutil -extract "$types.CFBundleTypeName" raw "$plist")" = "Markdown document" ] || fail "the bundle declares no Markdown document"
    [ "$(plutil -extract "$types.CFBundleTypeExtensions.0" raw "$plist")" = md ] || fail "the bundle's Markdown type lists no md"
    [ "$(plutil -extract "$types.CFBundleTypeMIMETypes.0" raw "$plist")" = text/markdown ] || fail "the bundle's Markdown type lists no text/markdown"
    [ "$(plutil -extract "$types.LSHandlerRank" raw "$plist")" = Alternate ] || fail "the bundle ranks itself other than Alternate"
    echo "ok: the bundle declares Markdown documents"
    # Finder's double-click: open -a starts the app through Launch
    # Services, which hands it the document in an Apple event, and the
    # launcher gives the program its path in ARGV. open passes the
    # environment on with --env, and waits with -W.
    set -- /usr/bin/open -n -W --env TMPDIR="$work/tmp/" --env BROWSER="$work/browser" -a "$root/$name.app" "$work/notes.md"
    ;;
  Linux)
    desktop=$(find "$root" -maxdepth 1 -name '*.desktop' | head -1)
    [ -n "$desktop" ] || fail "the folder holds no desktop entry"
    [ "$(sed -n 's/^MimeType=//p' "$desktop")" = "text/markdown;" ] || fail "the desktop entry's MimeType is not text/markdown"
    exec_line=$(sed -n 's/^Exec=//p' "$desktop")
    case "$exec_line" in *" %F") ;; *) fail "the desktop entry's Exec, $exec_line, does not end in %F" ;; esac
    echo "ok: the desktop entry declares text/markdown"
    set -- "$root/$name" "$work/notes.md"
    ;;
  *) fail "no delivery of markdown_preview for $(uname -s)" ;;
esac

# The recorder's own $1 is the page it is handed, not this script's.
# shellcheck disable=SC2016
printf '#!/bin/sh\nprintf "%%s\\n" "$1" > "%s/opened"\n' "$work" >"$work/browser"
chmod +x "$work/browser"
status=0
(cd / && env -i PATH="$work/empty-path" HOME="$work" TMPDIR="$work/tmp/" BROWSER="$work/browser" "$@") 2>"$work/err" || status=$?
[ "$status" -eq 0 ] || { cat "$work/err"; fail "$name exited with $status"; }
page="$work/tmp/markdown-preview/notes.html"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$work/opened" ] && break; sleep 1; done
[ "$(cat "$work/opened" 2>/dev/null)" = "$page" ] || fail "$name did not open $page in the browser: $(cat "$work/opened" 2>/dev/null)"
missing=$(grep -vxF -f "$page" "$expected" || true)
[ -z "$missing" ] || fail "the preview lacks these lines of the file's HTML: $missing"
echo "ok: $name wrote the preview and opened it in the browser"

echo "Delivered: $name and md2html, with Markdown declared"
