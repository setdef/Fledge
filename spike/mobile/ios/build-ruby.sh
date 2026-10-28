#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Spike (throwaway): cross-build CRuby 4.0.9 for one iOS slice, statically,
# with its extensions linked in, interpreter only, after xord/cruby's
# Rakefile (github.com/xord/cruby at 11d62c4, lines 499-724), and stage
# the Ruby tree an app bundle carries.
#
#   ios/build-ruby.sh iphoneos|iphonesimulator   (arm64 only)
#
# Output: $OUT/<sdk>/libfledgeruby.a (Ruby, its extensions and encodings,
# OpenSSL, libyaml, in one archive) and $OUT/<sdk>/root/lib/ruby/... (the
# standard library, default and bundled gems), $OUT/<sdk>/build.log.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../sources.sh"

sdk=${1:?iphoneos or iphonesimulator}
arch=arm64
min=15.0
OUT=${OUT:-$here/../out/ios}
case $sdk in
  iphoneos) target=arm64-apple-ios$min; ossl_target=ios64-xcrun; minflag=-mios-version-min=$min ;;
  iphonesimulator) target=arm64-apple-ios$min-simulator; ossl_target=iossimulator-arm64-xcrun; minflag=-mios-simulator-version-min=$min ;;
  *) echo "unknown sdk $sdk" >&2; exit 2 ;;
esac
sysroot=$(xcrun --sdk "$sdk" --show-sdk-path)
work=$OUT/$sdk/work
deps=$OUT/deps-$sdk
root=$OUT/$sdk/root
rm -rf "$OUT/$sdk"; mkdir -p "$work" "$root" "$deps"
exec > >(tee "$OUT/$sdk/build.log") 2>&1
start=$(date +%s)

CC="$(xcrun --sdk "$sdk" --find clang) -target $target -isysroot $sysroot"
export IPHONEOS_DEPLOYMENT_TARGET=$min

# libyaml (MIT)
[ -f "$deps/yaml/lib/libyaml.a" ] || { tar xzf "$(fetch "$YAML_URL" "$YAML_SHA256")" -C "$work"
(cd "$work/yaml-0.2.5" &&
  ./configure -q --host=aarch64-apple-darwin --prefix="$deps/yaml" --enable-static --disable-shared CC="$CC" CFLAGS="-Os" &&
  make -s -j"$(ncpu)" && make -s install) >/dev/null; }
echo "libyaml: $(( $(date +%s) - start ))s"

# OpenSSL (Apache-2.0); no-shared, no apps or tests, its own iOS targets.
[ -f "$deps/openssl/lib/libssl.a" ] || { tar xzf "$(fetch "$OPENSSL_URL" "$OPENSSL_SHA256")" -C "$work"
(cd "$work/openssl-3.6.3" &&
  ./Configure "$ossl_target" no-shared no-tests no-apps no-docs no-module \
    "$minflag" --prefix="$deps/openssl" --libdir=lib &&
  make -s -j"$(ncpu)" build_libs && make -s install_dev) >/dev/null; }
echo "openssl: $(( $(date +%s) - start ))s"

# Ruby
tar xzf "$(fetch "$RUBY_URL" "$RUBY_SHA256")" -C "$work"
src=$work/ruby-$RUBY_VERSION
# xord/cruby (Rakefile lines 546-564): the iOS SDK has no sys/vnode.h,
# which dir.c includes on Apple platforms for VREG/VDIR/VLNK and the
# filesystem types; a stub with the values XNU uses.
mkdir -p "$work/stub/sys"
# SPDX-SnippetBegin
# SPDX-License-Identifier: MIT
# SPDX-SnippetCopyrightText: 2014 xord.org
# SPDX-SnippetComment: The stub sys/vnode.h from xord/cruby's Rakefile, lines 553-560, at 11d62c4
cat > "$work/stub/sys/vnode.h" <<'H'
#ifndef DUMMY_VNODE_H_INCLUDED
#define DUMMY_VNODE_H_INCLUDED
enum {VREG = 1, VDIR = 2, VLNK = 5, VT_HFS = 16, VT_CIFS = 23};
#endif
H
# SPDX-SnippetEnd
# xord/cruby (Rakefile lines 299-310): vm_dump.c calls system() to run
# a crash reporter; system() is unavailable on iOS.
perl -0pi -e 's/int r = system\(buf\);/#if defined(HAVE_SYSTEM)\n    int r = system(buf);\n#else\n    int r = -1;\n#endif/' "$src/vm_dump.c"

. "$here/../common-ruby-src.sh"
absorb_bundled_c_gems "$src" "fiddle rbs"

mkdir -p "$work/ruby-build"
cd "$work/ruby-build"
# Functions iOS declares but forbids or lacks (xord/cruby, Rakefile
# line 578): system, syscall, backtrace, getentropy, dup3, pipe2.
"$src/configure" -q \
  --host=aarch64-apple-darwin --target=aarch64-apple-darwin \
  --prefix=/ --enable-load-relative \
  --disable-shared --disable-dln --with-static-linked-ext \
  --disable-yjit --disable-zjit \
  --disable-install-doc --disable-install-rdoc \
  --with-baseruby="$(command -v ruby)" \
  --with-openssl-dir="$deps/openssl" --with-libyaml-dir="$deps/yaml" \
  --without-gmp --with-out-ext=fiddle,win32,win32ole \
  ac_cv_func_system=no ac_cv_func_syscall=no ac_cv_func___syscall=no \
  ac_cv_func_backtrace=no ac_cv_func_getentropy=no ac_cv_func_dup3=no \
  ac_cv_func_pipe2=no ac_cv_func_setpgrp_void=yes \
  CC="$CC" CXX="$(xcrun --sdk "$sdk" --find clang++) -target $target -isysroot $sysroot" \
  PKG_CONFIG=false CPPFLAGS="-I$work/stub" CFLAGS="-Os -fvisibility=hidden" LDFLAGS="-framework Security"
echo "configure: $(( $(date +%s) - start ))s"
build_host_miniruby "$src" "$OUT/host-miniruby"
use_host_builtin_binary "$work/ruby-build" "$src" "$OUT/host-miniruby"
echo "host miniruby and builtin binary: $(( $(date +%s) - start ))s"
make -j"$(ncpu)" > "$OUT/$sdk/make.log" 2>&1 || { tail -150 "$OUT/$sdk/make.log"; exit 1; }
echo "make: $(( $(date +%s) - start ))s"
make -s install-nodoc DESTDIR="$root" 2>&1 | tail -20
echo "install: $(( $(date +%s) - start ))s"

# One archive per slice: libruby-static, every extension's archive,
# extinit.o and encinit.o (which register them), OpenSSL and libyaml
# (xord/cruby, Rakefile lines 684-724, which unpacks and repacks objects;
# Apple's libtool merges archives directly).
archives=$(find . -name '*.a' ! -path './libruby.a' | grep -v -E 'dmyext|dmyenc' | sort)
libtool -static -no_warning_for_no_symbols -o "$OUT/$sdk/libfledgeruby.a" \
  $archives ext/extinit.o enc/encinit.o \
  "$deps/openssl/lib/libssl.a" "$deps/openssl/lib/libcrypto.a" "$deps/yaml/lib/libyaml.a"
# libruby-static.a carries dmyext.o and dmyenc.o, empty Init_ext and
# Init_enc for a Ruby with no static extensions; the linker would take
# them before extinit.o and encinit.o (xord/cruby excludes them too,
# Rakefile line 686).
ar -d "$OUT/$sdk/libfledgeruby.a" dmyext.o dmyenc.o && ranlib "$OUT/$sdk/libfledgeruby.a" 2>/dev/null
ls -la "$OUT/$sdk/libfledgeruby.a"
echo "statically linked extensions:"; grep -o 'init(Init_[a-z0-9_]*, "[^"]*"' ext/extinit.c | sed 's/.*"\(.*\)"/\1/' | tr '\n' ' '; echo
echo "done: $(( $(date +%s) - start ))s"
