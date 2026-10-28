#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Spike (throwaway): stage what build-ruby.sh built into the Gradle
# project (jniLibs for each ABI built, the Ruby tree and app/ as one
# stored zip asset), build the APK, and check every native library for
# 16 KB pages: each LOAD segment aligned to 16 KB (llvm-readelf), and
# each .so stored 16 KB-aligned in the APK (zipalign -c -P 16).
#
#   GRADLE=/path/to/gradle android/build-apk.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$here/../out/android}
project=$here/project
main=$project/app/src/main
rm -rf "$main/jniLibs" "$main/assets" "$OUT/stage"
mkdir -p "$main/assets" "$OUT/stage/app"
start=$(date +%s)

tree=""
for abi in arm64-v8a x86_64; do
  [ -f "$OUT/$abi/libfledgeapp.so" ] || continue
  mkdir -p "$main/jniLibs/$abi"
  cp "$OUT/$abi/libfledgeapp.so" "$main/jniLibs/$abi/"
  tree=$OUT/$abi/root
done
# The Ruby library is the same Ruby files for every ABI except
# rbconfig.rb and the arch folder; the spike ships each ABI's arch folder.
rsync -a --exclude '*.a' --exclude pkgconfig "$tree/lib/" "$OUT/stage/lib/"
for abi in arm64-v8a x86_64; do
  [ -d "$OUT/$abi/root" ] || continue
  rsync -a --include '*/' --include 'rbconfig.rb' --exclude '*' "$OUT/$abi/root/lib/" "$OUT/stage/lib/"
done
cp "$here/../app/main.rb" "$OUT/stage/app/main.rb"
(cd "$OUT/stage" && zip -qr -X "$main/assets/fledge.zip" lib app)
ls -la "$main/assets/fledge.zip"

cd "$project"
"${GRADLE:-gradle}" --no-daemon -q assembleDebug
apk=$project/app/build/outputs/apk/debug/app-debug.apk
cp "$apk" "$OUT/FledgeSpike-debug.apk"
echo "built $OUT/FledgeSpike-debug.apk in $(( $(date +%s) - start ))s"; ls -la "$OUT/FledgeSpike-debug.apk"

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
bt=$(ls -d "$sdk"/build-tools/* | sort -V | tail -1)
echo "zipalign: $bt"
"$bt/zipalign" -c -P 16 -v 4 "$OUT/FledgeSpike-debug.apk" | grep -E '\.so|Verification'
readelf=$(ls "${ANDROID_NDK_ROOT:-$HOME/.cache/fledge-spike-mobile/android-ndk-r30}"/toolchains/llvm/prebuilt/*/bin/llvm-readelf)
rm -rf "$OUT/apk-unzipped"; mkdir -p "$OUT/apk-unzipped"
(cd "$OUT/apk-unzipped" && unzip -q "$OUT/FledgeSpike-debug.apk")
fail=0
for so in $(find "$OUT/apk-unzipped/lib" -name '*.so'); do
  for align in $("$readelf" -lW "$so" | awk '/LOAD/ {print $NF}'); do
    if [ $((align)) -lt 16384 ]; then echo "NOT 16 KB aligned: $so ($align)"; fail=1; fi
  done
  echo "16 KB LOAD alignment OK: ${so#$OUT/apk-unzipped/}"
done
"$bt/aapt2" dump badging "$OUT/FledgeSpike-debug.apk" | grep -E "sdkVersion|targetSdkVersion|native-code"
exit $fail
