#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Spike (throwaway): install the APK on the running emulator, start it,
# wait for Ruby to finish, and print logcat's FledgeRuby lines. Fails
# unless FLEDGE-SPIKE-OK appears. Runs inside android-emulator-runner.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$here/../out/android}
log=${1:-$OUT/logcat.txt}
echo "device: $(adb shell getprop ro.product.cpu.abi) API $(adb shell getprop ro.build.version.sdk), page size $(adb shell getconf PAGE_SIZE)"
adb install -r "$OUT/FledgeSpike-debug.apk"
adb logcat -c
start=$(date +%s)
adb shell am start -W -n org.setdef.fledge.spike/.MainActivity
for _ in $(seq 1 90); do
  adb logcat -d -s FledgeRuby:V | grep -q 'FLEDGE-SPIKE-RUBY' && break
  sleep 2
done
echo "Ruby finished $(( $(date +%s) - start ))s after am start"
adb logcat -d -s FledgeRuby:V > "$log"
adb logcat -d | grep -E 'FATAL|AndroidRuntime|DEBUG.*signal|linker' | head -40 || true
cat "$log"
grep -q 'FLEDGE-SPIKE-OK' "$log"
# A second launch reuses the extracted tree (no extraction cost).
adb shell am force-stop org.setdef.fledge.spike
adb logcat -c
adb shell am start -W -n org.setdef.fledge.spike/.MainActivity
for _ in $(seq 1 60); do
  adb logcat -d -s FledgeRuby:V | grep -q 'FLEDGE-SPIKE-RUBY' && break
  sleep 2
done
adb logcat -d -s FledgeRuby:V | grep -E 'FLEDGE-SPIKE-(EXTRACT|RUBY|STATUS|OK)'
echo PASS
