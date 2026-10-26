#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Shows that whoever receives a Linux app can replace its LGPL library,
# lib/libcrypt.so.2, as the LGPL asks (LGPL-2.1 section 6b), and measures
# what String#crypt does with each replacement.
#
#   replace-libcrypt.sh APP_DIR PROGRAM LIBXCRYPT_TARBALL MUSL_TARBALL
#
# APP_DIR is an unpacked app; PROGRAM its launcher's name. The script
# builds two libraries the runtime did not ship: libxcrypt from the same
# source with only its strong hashes (a modified build, which must change
# what the app does), and musl's crypt (MIT, BSD-3-Clause, and public
# domain) built as an interface-compatible libcrypt.so.2. It runs
# crypt_formats.rb as the app with the runtime's library and with each
# replacement, checks with ldd that the app loaded the file in its own
# lib/, and prints the results side by side (and into
# $GITHUB_STEP_SUMMARY in CI).

set -eu

app_dir=$(cd "$1" && pwd)
program="$app_dir/$2"
xcrypt_tarball=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
musl_tarball=$(cd "$(dirname "$4")" && pwd)/$(basename "$4")
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
  echo "replace-libcrypt: $*" >&2
  exit 1
}

cp "$here/crypt_formats.rb" "$app_dir/app/main.rb"
cp "$app_dir/lib/libcrypt.so.2" "$work/libcrypt-runtime.so.2"

# libxcrypt, modified: only the hashes its configure calls strong.
mkdir "$work/xcrypt"
tar -xJf "$xcrypt_tarball" -C "$work/xcrypt" --strip-components=1
(
  cd "$work/xcrypt"
  ./configure --quiet --prefix="$work/xcrypt-prefix" --enable-shared --disable-static --disable-obsolete-api \
    --disable-xcrypt-compat-files --disable-failure-tokens --disable-valgrind --enable-hashes=strong
  make --quiet -j"$(nproc)" >/dev/null
  make --quiet install >/dev/null
)
cp "$work/xcrypt-prefix/lib/libcrypt.so.2" "$work/libcrypt-strong.so.2"

# musl's crypt, as libcrypt.so.2: the launcher needs crypt_r at the
# symbol version XCRYPT_2.0, which a version script provides.
mkdir "$work/musl" "$work/musl-include"
tar -xzf "$musl_tarball" -C "$work/musl" --strip-components=1
cat >"$work/musl-include/crypt.h" <<'HEADER'
#ifndef CRYPT_H
#define CRYPT_H
#include <stdint.h>
#define hidden __attribute__((__visibility__("hidden")))
#define weak_alias(old, new) extern __typeof(old) new __attribute__((__weak__, __alias__(#old)))
struct crypt_data { int initialized; char __buf[256]; };
char *crypt_r(const char *, const char *, struct crypt_data *);
hidden char *__crypt_des(const char *, const char *, char *);
hidden char *__crypt_md5(const char *, const char *, char *);
hidden char *__crypt_blowfish(const char *, const char *, char *);
hidden char *__crypt_sha256(const char *, const char *, char *);
hidden char *__crypt_sha512(const char *, const char *, char *);
#endif
HEADER
echo 'XCRYPT_2.0 { global: crypt_r; local: *; };' >"$work/musl.map"
crypt="$work/musl/src/crypt"
cc -shared -fPIC -O2 -I"$work/musl-include" -include "$work/musl-include/crypt.h" -Wl,-soname,libcrypt.so.2 \
  -Wl,--version-script="$work/musl.map" -o "$work/libcrypt-musl.so.2" \
  "$crypt/crypt_r.c" "$crypt/crypt_des.c" "$crypt/crypt_md5.c" "$crypt/crypt_sha256.c" "$crypt/crypt_sha512.c" \
  "$crypt/crypt_blowfish.c"

run_with() {
  cp "$work/libcrypt-$1.so.2" "$app_dir/lib/libcrypt.so.2"
  loaded=$(ldd "$program" | sed -n 's/^[[:space:]]*libcrypt\.so\.2 => \(.*\) (0x[0-9a-f]*)$/\1/p')
  [ "$loaded" = "$app_dir/lib/libcrypt.so.2" ] || fail "with $1, libcrypt.so.2 resolves to '$loaded'"
  env -i PATH=/usr/bin:/bin HOME="$work" "$program" >"$work/out-$1.tsv" || fail "the app failed with the $1 libcrypt"
  echo "ok: the app ran with the $1 libcrypt.so.2 ($(sha256sum "$app_dir/lib/libcrypt.so.2" | cut -c1-16))"
}

run_with runtime
run_with strong
run_with musl
cp "$work/libcrypt-runtime.so.2" "$app_dir/lib/libcrypt.so.2"

cut -f3 "$work/out-runtime.tsv" | grep -q '^error' && fail "the runtime's libxcrypt refused a format: $(cat "$work/out-runtime.tsv")"
[ "$(sed -n 1p "$work/out-strong.tsv" | cut -f3)" = "error: Errno::EINVAL" ] ||
  fail "the modified libxcrypt (no DES) still computed DES, so the app did not use it"
# shellcheck disable=SC2016 # The dollar signs are the formats' own.
for format in 'MD5 ($1$)' 'SHA-256 ($5$)' 'SHA-512 ($6$)' 'bcrypt ($2b$)' 'DES'; do
  [ "$(grep -F "$format	" "$work/out-runtime.tsv")" = "$(grep -F "$format	" "$work/out-musl.tsv")" ] ||
    fail "musl's crypt differs from libxcrypt's for $format"
done

if command -v ruby >/dev/null; then
  ruby "$here/crypt_formats.rb" >"$work/out-system.tsv"
  system="system Ruby ($(ruby -e 'print RUBY_VERSION'))"
else
  printf '' >"$work/out-system.tsv"
  system="system Ruby (none)"
fi

report() {
  echo "| Format | Setting | runtime's libxcrypt | modified libxcrypt (strong only) | musl's crypt | $system |"
  echo "|---|---|---|---|---|---|"
  paste "$work/out-runtime.tsv" "$work/out-strong.tsv" "$work/out-musl.tsv" "$work/out-system.tsv" |
    awk -F '\t' '{ printf "| %s | `%s` | `%s` | `%s` | `%s` | `%s` |\n", $1, $2, $3, $6, $9, $12 }'
}
report
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  report >>"$GITHUB_STEP_SUMMARY"
fi
echo "Replaced lib/libcrypt.so.2 twice; the app used each replacement."
