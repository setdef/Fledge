#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Relinks rv-ruby's bin/ruby so that it loads libxcrypt as a shared
# library, the way Fledge's Linux launcher does, instead of carrying a
# static copy of it, which is LGPL code no recipient could replace.
#
#   relink-ruby.sh PREFIX LIBXCRYPT_TARBALL
#
# PREFIX is rv-ruby's unpacked Ruby (the folder holding bin/ and lib/).
# The script builds libxcrypt from the tarball with the runtime builder's
# options, links a new bin/ruby from Ruby's own main (main.c at Ruby
# 4.0.9, lines 36 to 64, without the debug options a release build leaves
# out) and rv-ruby's static libruby, with an RPATH of $ORIGIN/../lib,
# puts libcrypt.so.2 in PREFIX/lib, and removes rv-ruby's libcrypt.a.

set -eu

prefix=$(cd "$1" && pwd)
tarball=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/xcrypt"
tar -xJf "$tarball" -C "$work/xcrypt" --strip-components=1
(
  cd "$work/xcrypt"
  ./configure --quiet --prefix="$work/xcrypt-prefix" --enable-shared --disable-static --disable-obsolete-api \
    --disable-xcrypt-compat-files --disable-failure-tokens --disable-valgrind
  make --quiet -j"$(nproc)" >/dev/null
  make --quiet install >/dev/null
)

cat >"$work/main.c" <<'MAIN'
#undef RUBY_EXPORT
#include "ruby.h"
#include <locale.h>

RUBY_GLOBAL_SETUP

static int
rb_main(int argc, char **argv)
{
    RUBY_INIT_STACK;
    ruby_init();
    return ruby_run_node(ruby_options(argc, argv));
}

int
main(int argc, char **argv)
{
    setlocale(LC_CTYPE, "");
    ruby_sysinit(&argc, &argv);
    return ruby_start_main(rb_main, argc, argv);
}
MAIN

headers=$(ls -d "$prefix"/include/ruby-*)
arch=$(find "$headers" -mindepth 1 -maxdepth 1 -type d ! -name ruby | head -n 1)
# shellcheck disable=SC2016 # $ORIGIN is for the dynamic linker, not the shell.
cc -O2 -I"$arch" -I"$headers" "$work/main.c" -rdynamic -static-libgcc \
  -Wl,--whole-archive "$prefix/lib/libruby-static.a" -Wl,--no-whole-archive \
  -L"$work/xcrypt-prefix/lib" -lcrypt -Wl,--disable-new-dtags,-rpath,'$ORIGIN/../lib' \
  -lrt -ldl -lm -lpthread -o "$work/ruby"
strip --strip-unneeded "$work/ruby"
chmod -R u+w "$prefix/bin" "$prefix/lib"
cp "$work/ruby" "$prefix/bin/ruby"
cp "$(readlink -f "$work/xcrypt-prefix/lib/libcrypt.so.2")" "$prefix/lib/libcrypt.so.2"
rm -f "$prefix/lib/libcrypt.a"

readelf -d "$prefix/bin/ruby" | grep -E 'NEEDED|RPATH'
crypt=$(ldd "$prefix/bin/ruby" | sed -n 's/^[[:space:]]*libcrypt\.so\.2 => \(.*\) (0x[0-9a-f]*)$/\1/p')
[ "$(readlink -f "$crypt")" = "$prefix/lib/libcrypt.so.2" ] || { echo "relink-ruby: libcrypt.so.2 resolves to '$crypt'" >&2; exit 1; }
env -i PATH=/usr/bin:/bin "$prefix/bin/ruby" --yjit -ropenssl -ryaml -rzlib -e '
  abort "YJIT is off" unless RubyVM::YJIT.enabled?
  abort "wrong prefix: #{RbConfig::TOPDIR}" unless RbConfig::TOPDIR == ARGV.fetch(0)
  puts RUBY_DESCRIPTION, OpenSSL::OPENSSL_LIBRARY_VERSION, YAML.dump("crypt" => "x".crypt("ab"))
' "$prefix"
echo "Relinked $prefix/bin/ruby against $prefix/lib/libcrypt.so.2"
