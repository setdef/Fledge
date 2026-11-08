#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Delivery of an app whose gem loads a library from the Linux
# distribution (ADR 030) on Debian and Ubuntu: examples/system_library,
# whose png_version gem links libpng16.so.16, on a computer that has never
# seen Ruby and has no libpng until apt brings it.
#
#   deliver-system-library.sh FOLDER
#
# FOLDER holds "System Library-PLATFORM.tar.gz", ".AppImage", and ".deb".
# Before apt installs anything, the archive's program and the AppImage,
# extracted as a computer without FUSE runs it, must say which library is
# missing and exit with 72, naming no gem; the .deb must depend on the
# package that provides libpng16.so.16, which apt must then install with
# it; and the installed program, and the archive's, must run and print the
# libpng the computer has.
#
# This is POSIX sh on purpose: nothing here may need Ruby.

set -eu

folder=$(cd "$1" && pwd)
name="System Library"
package=com.setdef.fledge.systemlibrary
platform=$(dpkg --print-architecture)
case "$platform" in
  amd64) platform=x86_64-linux ;;
  arm64) platform=aarch64-linux ;;
esac

fail() {
  echo "::error::Delivery (system library): $*" >&2
  exit 1
}

# missing LABEL COMMAND...: COMMAND exits with 72 and names libpng16.so.16
# and nothing of Ruby's.
missing() {
  label=$1
  shift
  status=0
  out=$("$@" 2>&1) || status=$?
  echo "$label: $out"
  [ "$status" -eq 72 ] || fail "$label exited with $status, not 72"
  printf '%s' "$out" | grep -q "this app needs libpng16\.so\.16, which this computer does not have" || fail "$label did not name libpng16.so.16"
  if printf '%s' "$out" | grep -qi "ruby\|png_version\|LoadError"; then
    fail "$label named Ruby or a gem"
  fi
  echo "ok: $label names the missing library and exits with 72"
}

# runs LABEL COMMAND...: COMMAND prints the libpng it loaded and exits 0.
runs() {
  label=$1
  shift
  out=$("$@" 2>&1) || fail "$label failed: $out"
  printf '%s' "$out" | grep -q "^png_version loaded libpng 1\.6\.[0-9]* from the system$" || fail "$label printed: $out"
  echo "ok: $label: $out"
}

if ls /usr/lib/*/libpng16.so.16 >/dev/null 2>&1; then
  fail "this computer has libpng before the test begins"
fi

work=$(mktemp -d)
tar -xzf "$folder/$name-$platform.tar.gz" -C "$work"
archived="$work/$name-$platform/$name"
missing "the archive's program" env -i PATH=/usr/bin:/bin "$archived"

image="$folder/$name-$platform.AppImage"
chmod +x "$image"
(cd "$work" && missing "the AppImage" env -i PATH=/usr/bin:/bin APPIMAGE_EXTRACT_AND_RUN=1 "$image")

depends=$(dpkg-deb --field "$folder/$name-$platform.deb" Depends)
echo "Depends: $depends"
printf '%s' "$depends" | grep -Eq "^libc6 \(>= 2\.39\), libpng16-16t64 \(>= [^)]+\)$" || fail "the .deb depends on '$depends'"
echo "ok: the .deb depends on libc6 and libpng16-16t64"

DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$folder/$name-$platform.deb" >/dev/null || fail "apt could not install the .deb"
ls /usr/lib/*/libpng16.so.16 >/dev/null 2>&1 || fail "apt installed the .deb without libpng"
echo "ok: apt installed $package and libpng with it"

runs "the installed program" env -i PATH=/usr/bin:/bin "/usr/lib/$package/$name"
runs "the archive's program, with libpng installed" env -i PATH=/usr/bin:/bin "$archived"

DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "$package" >/dev/null || fail "apt could not remove $package"
[ ! -e "/usr/lib/$package" ] || fail "/usr/lib/$package remains"
echo "ok: apt removed $package"
