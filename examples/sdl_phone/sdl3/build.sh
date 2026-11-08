#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#
# Builds SDL3 for each target of a phone, from SDL's release tarball,
# pinned by version and SHA-256, with SDL's own CMake build, which
# docs/README-cmake.md describes for iOS (lines 178 to 264) and
# docs/README-android.md for Android with the NDK's toolchain file
# (lines 602 to 612), at release-3.4.18:
#
#   sdl3/build.sh ios OUT        # on a Mac, with Xcode
#   sdl3/build.sh android OUT    # with ANDROID_NDK_ROOT set
#
# It writes OUT/TARGET/include and OUT/TARGET/lib for each target, the
# names the gem's extconf.rb looks for: ios-arm64 and
# ios-arm64-simulator, static libraries, which link into the app's
# executable as Fledge links extensions on iOS (ADR 022); and arm64-v8a
# and x86_64, shared libraries, since SDL's Java side loads libSDL3.so
# by name (SDLActivity.getLibraries) and SDL registers its Java methods
# from that library's JNI_OnLoad (src/core/android/SDL_android.c, lines
# 578 to 606). For Android it also copies SDL's Java classes, which the
# Gradle project compiles, into the example's Android host, at
# host/android/src/main/java/org/libsdl/app, where SDL's own
# android-project holds them (docs/README-android.md, line 124), so that
# fledge build android copies them into the project with the host's
# MainActivity (ADR 025). Git ignores them there.
#
# Point the gem at OUT with Bundler: bundle config build.sdl_demo
# --with-sdl3-builds=OUT, or BUNDLE_BUILD__SDL_DEMO in the environment.
set -euo pipefail

version=3.4.18
sha256=9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3
url="https://github.com/libsdl-org/SDL/releases/download/release-$version/SDL3-$version.tar.gz"

system=${1:?usage: build.sh ios|android OUT}
out=$(mkdir -p "${2:?usage: build.sh ios|android OUT}" && cd "$2" && pwd)
work="$out/work"
tarball="$work/SDL3-$version.tar.gz"
source="$work/SDL3-$version"
mkdir -p "$work"

if [ ! -f "$tarball" ]; then
  curl --fail --silent --show-error --location --output "$tarball.part" "$url"
  mv "$tarball.part" "$tarball"
fi
actual=$(shasum -a 256 "$tarball" | cut -d ' ' -f 1)
if [ "$actual" != "$sha256" ]; then
  echo "build.sh: $tarball has SHA-256 $actual, not $sha256" >&2
  exit 1
fi
rm -rf "$source"
tar -xzf "$tarball" -C "$work"

# Configures, builds, and installs SDL into OUT/$1, with the rest of the
# arguments for CMake.
build() {
  local target=$1
  shift
  cmake -S "$source" -B "$work/build-$target" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$out/$target" -DCMAKE_INSTALL_LIBDIR=lib -DSDL_TEST_LIBRARY=OFF -DSDL_EXAMPLES=OFF "$@"
  cmake --build "$work/build-$target" --parallel
  cmake --install "$work/build-$target"
}

case "$system" in
  ios)
    for sdk in iphoneos iphonesimulator; do
      target=ios-arm64
      [ "$sdk" = iphonesimulator ] && target=ios-arm64-simulator
      build "$target" -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DSDL_SHARED=OFF -DSDL_STATIC=ON
    done
    ;;
  android)
    toolchain="${ANDROID_NDK_ROOT:?set ANDROID_NDK_ROOT to the NDK}/build/cmake/android.toolchain.cmake"
    for abi in arm64-v8a x86_64; do
      build "$abi" -DCMAKE_TOOLCHAIN_FILE="$toolchain" -DANDROID_ABI="$abi" -DANDROID_PLATFORM=26 \
        -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_ANDROID_JAR=OFF
    done
    java="$(cd "$(dirname "$0")/.." && pwd)/host/android/src/main/java/org/libsdl"
    rm -rf "$java"
    mkdir -p "$java"
    cp -R "$source/android-project/app/src/main/java/org/libsdl/app" "$java/app"
    ;;
  *)
    echo "build.sh: $system is not ios or android" >&2
    exit 2
    ;;
esac
cp "$source/LICENSE.txt" "$out/LICENSE.txt"
