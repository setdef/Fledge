#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Spike (throwaway): cross-build CRuby 4.0.9 for one Android ABI with the
# NDK, statically, extensions linked in, interpreter only (Ruby's
# configure.ac, lines 3916-3933, never enables YJIT or ZJIT for
# *android*), configure flags after Termux's recipe
# (termux-packages/packages/ruby/build.sh), then link the JNI host into
# libfledgeapp.so and stage the Ruby tree the APK carries as assets.
#
#   android/build-ruby.sh arm64-v8a|x86_64
#
# Output: $OUT/<abi>/libfledgeapp.so, $OUT/<abi>/root/lib/ruby/...
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../sources.sh"
. "$here/../common-ruby-src.sh"

abi=${1:?arm64-v8a or x86_64}
api=26  # nl_langinfo (localeinit.c) is in bionic from API 26; Termux gets it from libandroid-support
OUT=${OUT:-$here/../out/android}
case $abi in
  arm64-v8a) triple=aarch64-linux-android; ossl_target=android-arm64 ;;
  x86_64) triple=x86_64-linux-android; ossl_target=android-x86_64 ;;
  *) echo "unknown ABI $abi" >&2; exit 2 ;;
esac

if [ -z "${ANDROID_NDK_ROOT:-}" ]; then
  case $(uname -s) in
    Darwin) zip=$(fetch "$NDK_DARWIN_URL" "$NDK_DARWIN_SHA256") ;;
    *) zip=$(fetch "$NDK_LINUX_URL" "$NDK_LINUX_SHA256") ;;
  esac
  [ -d "$SPIKE_CACHE/android-ndk-$NDK_VERSION" ] || (cd "$SPIKE_CACHE" && unzip -q "$zip")
  export ANDROID_NDK_ROOT=$SPIKE_CACHE/android-ndk-$NDK_VERSION
fi
host_tag=$(ls "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/")
tc=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$host_tag
CC="$tc/bin/$triple$api-clang"
CXX="$tc/bin/$triple$api-clang++"
AR=$tc/bin/llvm-ar
RANLIB=$tc/bin/llvm-ranlib

work=$OUT/$abi/work
deps=$OUT/deps-$abi
root=$OUT/$abi/root
rm -rf "$OUT/$abi"; mkdir -p "$work" "$root" "$deps"
exec > >(tee "$OUT/$abi/build.log") 2>&1
start=$(date +%s)
echo "NDK: $(grep Pkg.Revision "$ANDROID_NDK_ROOT/source.properties")"

# libyaml (MIT)
[ -f "$deps/yaml/lib/libyaml.a" ] || { tar xzf "$(fetch "$YAML_URL" "$YAML_SHA256")" -C "$work"
(cd "$work/yaml-0.2.5" &&
  ./configure -q --host=$triple --prefix="$deps/yaml" --enable-static --disable-shared --with-pic \
    CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="-O2 -fPIC" &&
  make -s -j"$(ncpu)" && make -s install) >/dev/null; }
echo "libyaml: $(( $(date +%s) - start ))s"

# libffi (MIT), for fiddle: nothing in Play's policy forbids it, unlike
# the App Store's (see FINDINGS.md).
[ -f "$deps/ffi/lib/libffi.a" ] || { tar xzf "$(fetch "$FFI_URL" "$FFI_SHA256")" -C "$work"
(cd "$work/libffi-3.5.2" &&
  ./configure -q --host=$triple --prefix="$deps/ffi" --enable-static --disable-shared --with-pic \
    --disable-docs --disable-multi-os-directory CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="-O2 -fPIC" &&
  make -s -j"$(ncpu)" && make -s install) >/dev/null; }
echo "libffi: $(( $(date +%s) - start ))s"

# OpenSSL (Apache-2.0), its own android targets, static, no apps.
[ -f "$deps/openssl/lib/libssl.a" ] || { tar xzf "$(fetch "$OPENSSL_URL" "$OPENSSL_SHA256")" -C "$work"
(cd "$work/openssl-3.6.3" && export PATH=$tc/bin:$PATH &&
  ./Configure "$ossl_target" -D__ANDROID_API__=$api no-shared no-tests no-apps no-docs no-module \
    --prefix="$deps/openssl" --libdir=lib &&
  make -s -j"$(ncpu)" build_libs && make -s install_dev) >/dev/null; }
echo "openssl: $(( $(date +%s) - start ))s"

tar xzf "$(fetch "$RUBY_URL" "$RUBY_SHA256")" -C "$work"
src=$work/ruby-$RUBY_VERSION
absorb_bundled_c_gems "$src" "rbs"
# The one source change Android needs (iOS does not): with
# --enable-load-relative, ruby_init_loadpath takes Ruby's prefix from
# the path of the binary holding libruby (dladdr). On Android that is
# the APK's native library folder, which holds only lib*.so files, so
# the standard library has to live elsewhere (the app's files folder,
# extracted from assets). ruby_embed_libruby_path lets the host name the
# path Ruby would otherwise read from dladdr.
perl -0pi -e 's|(#elif defined\(HAVE_DLADDR\)\n    Dl_info dli;\n    VALUE fname, path;\n    const void\* addr = \(void \*\)\(VALUE\)expand_include_path;\n)|$1\n    {\n        extern const char *ruby_embed_libruby_path;\n        if (ruby_embed_libruby_path) return rb_str_new_cstr(ruby_embed_libruby_path);\n    }\n|' "$src/ruby.c"
printf '\nconst char *ruby_embed_libruby_path;\n' >> "$src/ruby.c"
grep -q 'if (ruby_embed_libruby_path)' "$src/ruby.c"

mkdir -p "$work/ruby-build"; cd "$work/ruby-build"
"$src/configure" -q \
  --host=$triple --target=$triple \
  --prefix=/ --enable-load-relative \
  --disable-shared --with-static-linked-ext \
  --disable-yjit --disable-zjit \
  --disable-install-doc --disable-install-rdoc \
  --with-baseruby="$(command -v ruby)" \
  --with-openssl-dir="$deps/openssl" --with-libyaml-dir="$deps/yaml" --with-libffi-dir="$deps/ffi" \
  --without-gmp --with-out-ext=win32,win32ole \
  ac_cv_func_setgroups=no ac_cv_func_setresuid=no ac_cv_func_setreuid=no \
  ac_cv_lib_crypt_crypt=no rb_cv_type_deprecated=x \
  CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
  PKG_CONFIG=false CFLAGS="-O2 -fPIC -fno-strict-aliasing" CPPFLAGS="-I$deps/ffi/include" LDFLAGS="-L$deps/ffi/lib"
echo "configure: $(( $(date +%s) - start ))s"
build_host_miniruby "$src" "$OUT/host-miniruby"
use_host_builtin_binary "$work/ruby-build" "$src" "$OUT/host-miniruby"
echo "host miniruby and builtin binary: $(( $(date +%s) - start ))s"
make -j"$(ncpu)" > "$OUT/$abi/make.log" 2>&1 || { tail -150 "$OUT/$abi/make.log"; exit 1; }
echo "make: $(( $(date +%s) - start ))s"
make -s install-nodoc DESTDIR="$root" 2>&1 | tail -5
echo "install: $(( $(date +%s) - start ))s"

# One archive: libruby-static and every extension's archive, extinit.o
# and encinit.o, without dmyext.o and dmyenc.o (see ios/build-ruby.sh),
# then OpenSSL, libyaml, libffi.
lib=$OUT/$abi/libfledgeruby.a
rm -f "$lib"
for a in $(find . -name '*.a' | sort) "$deps/openssl/lib/libssl.a" "$deps/openssl/lib/libcrypto.a" \
         "$deps/yaml/lib/libyaml.a" "$deps/ffi/lib/libffi.a"; do
  "$AR" qcL "$lib" "$a"
done
"$AR" q "$lib" ext/extinit.o enc/encinit.o
"$AR" d "$lib" dmyext.o dmyenc.o
"$RANLIB" "$lib"
echo "statically linked extensions:"; grep -o 'init(Init_[a-z0-9_]*, "[^"]*"' ext/extinit.c | sed 's/.*"\(.*\)"/\1/' | tr '\n' ' '; echo

# The JNI host, linked into the one native library the APK carries.
# NDK r28 and later align LOAD segments to 16 KB by default; the flag
# says so anyway (Play requires it from 2027-02-01).
"$CC" -shared -fPIC -O2 -o "$OUT/$abi/libfledgeapp.so" "$here/app/jni/fledge_jni.c" \
  -I"$root/include/ruby-4.0.0" -I"$root/include/ruby-4.0.0/$( ls "$root/include/ruby-4.0.0" | grep android)" \
  "$lib" \
  -Wl,-z,max-page-size=16384 -Wl,--gc-sections -Wl,--exclude-libs,ALL \
  -llog -lz -ldl -lm
"$tc/bin/llvm-strip" --strip-unneeded "$OUT/$abi/libfledgeapp.so"
ls -la "$OUT/$abi/libfledgeapp.so"
"$tc/bin/llvm-readelf" -lW "$OUT/$abi/libfledgeapp.so" | awk '/LOAD/ {print "LOAD align", $NF}'
"$tc/bin/llvm-readelf" -dW "$OUT/$abi/libfledgeapp.so" | grep NEEDED
echo "done: $(( $(date +%s) - start ))s"
