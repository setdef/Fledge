#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

# Checks that the Android SDK bin/android-sdk laid out holds what the
# runtime's build and an emulator need, and that the tools mise.android.toml
# pins run. Run under MISE_ENV=android, after tasks/setup.rb and
# bin/android-sdk:
#
#   MISE_ENV=android mise x -- .github/scripts/check-android-sdk.sh
#
# The SDK is a folder of links to the packages mise installed, so each
# path is read through them.
set -euo pipefail
IFS=$'\n\t'

: "${ANDROID_HOME:?run this under mise with MISE_ENV=android}"
: "${ANDROID_NDK_ROOT:?run this under mise with MISE_ENV=android}"

for path in platform-tools/adb emulator/emulator platforms/android-36/android.jar; do
  [ -e "$ANDROID_HOME/$path" ] || { echo "::error::$ANDROID_HOME holds no $path"; exit 1; }
done
for image in google_apis google_apis_ps16k; do
  [ -d "$ANDROID_HOME/system-images/android-36/$image/x86_64" ] || { echo "::error::$ANDROID_HOME holds no system image $image"; exit 1; }
done
for folder in "$ANDROID_HOME"/build-tools/*; do
  [ -x "$folder/aapt2" ] || { echo "::error::$folder holds no aapt2"; exit 1; }
done
[ -d "$ANDROID_NDK_ROOT" ] || { echo "::error::ANDROID_NDK_ROOT, $ANDROID_NDK_ROOT, is no folder"; exit 1; }

java -version
cmake --version
"$ANDROID_HOME/platform-tools/adb" version
echo "The Android SDK in $ANDROID_HOME holds what it needs."
