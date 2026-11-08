#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Delivery of a windowed app's .deb (ADR 021) on Debian and Ubuntu: the
# .deb fledge build wrote for examples/windowed_app, installed with apt as
# root on a computer that has never seen Ruby, run, and removed.
#
#   deliver-deb.sh DEB
#
# DEB is "Hello Window-PLATFORM.deb". dpkg-deb must read the fields the
# build gave it, for this computer's architecture; apt must install it,
# resolving its dependency on a new enough glibc; the desktop entry
# desktop-file-validate accepts, and the icons, must be where desktops
# look, and update-desktop-database must list the app for the MIME type
# it opens; the program must run from /usr/lib/PACKAGE, as the desktop entry's
# Exec has it, as root and as an ordinary user, with a PATH that holds no
# Ruby and in a hostile Ruby environment, and write its report and exit
# with the status it is given; and removing the package must leave
# nothing of it behind.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

deb=$1
name="Hello Window"
identifier=com.setdef.fledge.HelloWindow
package=com.setdef.fledge.hellowindow
version=1.2.3

fail() {
  echo "::error::Delivery (.deb): $*" >&2
  exit 1
}

# expect LABEL ACTUAL EXPECTED
expect() {
  [ "$2" = "$3" ] || fail "$1 is '$2', not '$3'"
  echo "ok: $1 is $3"
}

[ "$(id -u)" -eq 0 ] || fail "this installs as root, in a container"
deb=$(cd "$(dirname "$deb")" && pwd)/$(basename "$deb")

expect Package "$(dpkg-deb --field "$deb" Package)" "$package"
expect Version "$(dpkg-deb --field "$deb" Version)" "$version"
expect Architecture "$(dpkg-deb --field "$deb" Architecture)" "$(dpkg --print-architecture)"
expect Depends "$(dpkg-deb --field "$deb" Depends)" "libc6 (>= 2.39)"
expect Homepage "$(dpkg-deb --field "$deb" Homepage)" "https://github.com/setdef/Fledge"
expect Description "$(dpkg-deb --field "$deb" Description)" "Says hello from a window
 Hello Window is the example windowed app of Fledge, which ships a Ruby
 app to people who don't have Ruby.
 .
 It opens no window: given a path, it writes a report there."

if dpkg -s "$package" >/dev/null 2>&1; then
  fail "$package is installed before the test begins"
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$deb" >/dev/null || fail "apt could not install $deb"
dpkg -s "$package" | grep -qx "Status: install ok installed" || fail "dpkg does not say $package is installed"
echo "ok: apt installed $package"

lib="/usr/lib/$package"
program="$lib/$name"
desktop="/usr/share/applications/$identifier.desktop"
[ -x "$program" ] || fail "$program is not executable"
expect "the program's owner" "$(stat -c %U:%G "$program")" root:root
grep -q "^This app was built with Fledge" "$lib/notices/NOTICES.txt" || fail "the app has no notices"
[ -f "$desktop" ] || fail "there is no $desktop"
[ ! -e "$lib/$identifier.desktop" ] || fail "the desktop entry is in the app's folder as well"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$desktop" || fail "desktop-file-validate rejects $desktop"
  echo "ok: desktop-file-validate accepts the desktop entry"
fi
expect Name "$(sed -n 's/^Name=//p' "$desktop")" "$name"
expect Comment "$(sed -n 's/^Comment=//p' "$desktop")" "Says hello from a window"
expect Exec "$(sed -n 's/^Exec=//p' "$desktop")" "\"$program\" %F"
expect MimeType "$(sed -n 's/^MimeType=//p' "$desktop")" "inode/directory;application/x-hellowindow;"
# dpkg's trigger runs update-desktop-database, from desktop-file-utils,
# which reads the MIME types of every desktop entry into the cache
# desktops look a file's apps up in.
if command -v update-desktop-database >/dev/null 2>&1; then
  grep -q "^application/x-hellowindow=.*$identifier.desktop" /usr/share/applications/mimeinfo.cache || fail "mimeinfo.cache does not name $identifier.desktop for application/x-hellowindow"
  echo "ok: update-desktop-database lists the app for application/x-hellowindow"
fi
expect Icon "$(sed -n 's/^Icon=//p' "$desktop")" "$identifier"
expect Terminal "$(sed -n 's/^Terminal=//p' "$desktop")" false
doc="/usr/share/doc/$package"
# Debian Policy 12.5: the license, uncompressed, as the installed copyright
# file. Debian's and Ubuntu's container images install no other file of
# /usr/share/doc (their dpkg.cfg.d excludes it), so the changelog is read
# from the package: changelog.gz (12.7), from gzip -n -9, with no name or
# time in its header.
grep -qx "MIT No Attribution" "$doc/copyright" || fail "$doc/copyright is not the app's license: $(head -n 3 "$doc/copyright")"
grep -q "^Copyright © 2026 setdef\$" "$doc/copyright" || fail "$doc/copyright lost its copyright line"
expect "the copyright file's mode" "$(stat -c %a "$doc/copyright")" 644
unpacked=$(mktemp -d)
dpkg-deb --extract "$deb" "$unpacked"
changelog="$unpacked$doc/changelog.gz"
zcat "$changelog" | grep -qx "Hello Window 1.2.3" || fail "the package's changelog.gz is not the app's changelog"
expect "changelog.gz's gzip header" "$(od -An -tx1 -N10 "$changelog" | sed 's/^ *//')" "1f 8b 08 00 00 00 00 00 02 03"
expect "changelog.gz's mode" "$(stat -c %a "$changelog")" 644
rm -rf "$unpacked"
png="89 50 4e 47 0d 0a 1a 0a"
icons=""
for size in 16 32 64 128 256 512; do
  icon="/usr/share/icons/hicolor/${size}x$size/apps/$identifier.png"
  expect "the ${size}-pixel icon's first bytes" "$(od -An -tx1 -N8 "$icon" | sed 's/^ *//')" "$png"
  icons="$icons $icon"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
chmod 777 "$work"
empty="$work/empty-path"
mkdir -p "$empty"
if env -i PATH="$empty" /bin/sh -c 'command -v ruby' >/dev/null 2>&1; then
  fail "ruby is still reachable on the app's PATH"
fi
evil="$work/evil"
mkdir -p "$evil/lib"
echo 'raise "Delivery: the user'"'"'s Ruby environment leaked into the app"' >"$evil/json.rb"
echo "not a library" >"$evil/lib/libcrypt.so.2"
chmod -R a+rX "$evil"

# run LABEL [VAR=VALUE...]: runs the installed program from / as root in an
# empty environment plus VAR=VALUE..., and as nobody when LABEL begins
# with "nobody"; it must exit with 4, print nothing on standard error, and
# report this runtime's Ruby.
run() {
  label=$1
  shift
  report="$work/report-$$.json"
  rm -f "$report"
  as=""
  case "$label" in nobody*) as="$setpriv --reuid=65534 --regid=65534 --clear-groups" ;; esac
  set +e
  # shellcheck disable=SC2086 # $as is a command and its arguments
  (cd / && env -i PATH="$empty" HOME="$work" TMPDIR="$work" "$@" $as "$program" "$report" 4) >"$work/out" 2>"$work/err"
  status=$?
  set -e
  [ "$status" -eq 4 ] || { cat "$work/out" "$work/err"; fail "$label: exit status $status, not 4"; }
  [ ! -s "$work/err" ] || { cat "$work/err"; fail "$label: it wrote to standard error"; }
  grep -q '"ruby":"4.0.9"' "$report" || fail "$label: the report says another Ruby: $(cat "$report")"
  grep -q '"program":"main.rb","folder":"app"' "$report" || fail "$label: the report says another program: $(cat "$report")"
  echo "ok: $label ran and reported $(cat "$report")"
}

setpriv=$(command -v setpriv) || fail "this computer has no setpriv (util-linux), to run the app as an ordinary user"
run "root"
run "nobody, an ordinary user"
run "a hostile Ruby environment" RUBYLIB="$evil" RUBYOPT="-rjson" GEM_HOME="$evil" GEM_PATH="$evil" \
  BUNDLE_GEMFILE="$evil/Gemfile" LD_LIBRARY_PATH="$evil/lib"

DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "$package" >/dev/null || fail "apt could not remove $package"
if dpkg -s "$package" 2>/dev/null | grep -qx "Status: install ok installed"; then
  fail "dpkg still says $package is installed"
fi
for left in "$lib" "$desktop" "$doc" $icons; do
  [ ! -e "$left" ] || fail "removing the package left $left behind"
done
[ -z "$(dpkg --audit)" ] || fail "dpkg --audit has something to say: $(dpkg --audit)"
echo "ok: removing the package left nothing of it behind"

echo "Delivered: $name, as a .deb"
