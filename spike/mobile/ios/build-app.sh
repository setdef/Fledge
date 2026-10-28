#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Spike (throwaway): stage what build-ruby.sh built into the host app,
# generate its Xcode project with XcodeGen, and build it.
#
#   ios/build-app.sh iphonesimulator   -> out/ios/FledgeSpike-sim.app
#   ios/build-app.sh iphoneos          -> out/ios/FledgeSpike-unsigned.ipa
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
sdk=${1:?iphoneos or iphonesimulator}
OUT=${OUT:-$here/../out/ios}
app=$here/app
staged=$app/staged
rm -rf "$staged"; mkdir -p "$staged/include"
start=$(date +%s)

# One XCFramework holding whichever slices exist, as a developer's own
# Xcode project would consume it.
libs=()
for s in iphoneos iphonesimulator; do
  [ -f "$OUT/$s/libfledgeruby.a" ] || continue
  libs+=(-library "$OUT/$s/libfledgeruby.a")
  cp -R "$OUT/$s/root/include" "$staged/include/$s"
done
xcodebuild -create-xcframework "${libs[@]}" -output "$staged/FledgeRuby.xcframework" >/dev/null

# The Ruby library goes in the bundle's top folder, beside the
# executable, so --enable-load-relative finds it: Foo.app/lib/ruby/...
# Left out, as a desktop runtime prunes them (ADR 003, section 2): the
# static library, headers, pkg-config, and bin/ (an iOS bundle may not
# carry stray executables; there is no shell to run them).
mkdir -p "$staged/lib"
rsync -a --exclude '*.a' --exclude pkgconfig "$OUT/$sdk/root/lib/ruby" "$staged/lib/"
mkdir -p "$staged/app"
cp "$here/../app/main.rb" "$staged/app/main.rb"

cd "$app"
xcodegen generate --quiet
dd=$OUT/dd-$sdk
xcodebuild -project FledgeSpike.xcodeproj -scheme FledgeSpike -configuration Release \
  -sdk "$sdk" \
  -derivedDataPath "$dd" build CODE_SIGNING_ALLOWED=NO > "$OUT/xcodebuild-$sdk.log" 2>&1 ||
  { tail -60 "$OUT/xcodebuild-$sdk.log"; exit 1; }
product=$dd/Build/Products/Release-$sdk/FledgeSpike.app
echo "built $product in $(( $(date +%s) - start ))s"
du -sh "$product"
ls -la "$product/FledgeSpike"
if [ "$sdk" = iphoneos ]; then
  rm -rf "$OUT/Payload"; mkdir -p "$OUT/Payload"
  cp -R "$product" "$OUT/Payload/"
  (cd "$OUT" && rm -f FledgeSpike-unsigned.ipa && zip -qry FledgeSpike-unsigned.ipa Payload)
  ls -la "$OUT/FledgeSpike-unsigned.ipa"
  otool -l "$product/FledgeSpike" | grep -A4 LC_BUILD_VERSION | head -5
  echo "linked dylibs:"; otool -L "$product/FledgeSpike"
else
  rm -rf "$OUT/FledgeSpike-sim.app"; cp -R "$product" "$OUT/FledgeSpike-sim.app"
fi
