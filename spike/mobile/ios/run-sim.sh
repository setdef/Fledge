#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Spike (throwaway): boot a simulator of the given device type, install
# the app, run it until Ruby exits, and print what it wrote to stdout
# and to the unified log. Fails unless FLEDGE-SPIKE-OK appears.
#
#   ios/run-sim.sh "iPhone 17"     ios/run-sim.sh "iPad Air 11-inch (M3)"
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$here/../out/ios}
want=${1:-iPhone}
runtime=$(xcrun simctl list runtimes -j | ruby -rjson -e 'r = JSON.parse($stdin.read)["runtimes"].select { _1["platform"] == "iOS" && _1["isAvailable"] }.max_by { Gem::Version.new(_1["version"]) }; puts r["identifier"]')
# A device type the newest runtime supports: one of the runtime's own
# simulators named WANT, or else the newest starting with WANT's first word.
devtype=$(xcrun simctl list devices available -j | WANT="$want" RUNTIME="$runtime" ruby -rjson -e '
  devices = JSON.parse($stdin.read)["devices"][ENV["RUNTIME"]] || []
  family = ENV["WANT"].split.first
  d = devices.find { _1["name"] == ENV["WANT"] } || devices.reverse.find { _1["name"].start_with?(family) }
  abort "no #{family} simulator for #{ENV["RUNTIME"]}" unless d
  puts d["deviceTypeIdentifier"]')
name="fledge-spike-$(echo "$want" | tr -c 'A-Za-z0-9' '-')"
udid=$(xcrun simctl create "$name" "$devtype" "$runtime")
trap 'xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true' EXIT
echo "device $want ($devtype) on $runtime: $udid"
start=$(date +%s)
xcrun simctl bootstatus "$udid" -b >/dev/null
echo "booted in $(( $(date +%s) - start ))s"
xcrun simctl install "$udid" "$OUT/FledgeSpike-sim.app"
since=$(date '+%Y-%m-%d %H:%M:%S')
log=$OUT/sim-$(echo "$want" | tr -c 'A-Za-z0-9' '-').log
# --console-pty waits for the app to exit and shows its stdout and stderr.
# A first launch on a new device can wait for SpringBoard; give it time,
# and bound it (perl's alarm, since macOS has no timeout(1)).
for attempt in 1 2 3; do
  perl -e 'alarm shift; exec @ARGV' 240 xcrun simctl launch --console-pty --terminate-running-process \
    "$udid" org.setdef.fledge.spike -FledgeExitAfterRuby YES > "$log.stdout" 2>&1 || true
  grep -q FLEDGE-SPIKE-DONE "$log.stdout" && break
  echo "attempt $attempt did not finish; retrying"; sleep 10
done
echo "ran in $(( $(date +%s) - start ))s since boot started"
sleep 2
xcrun simctl spawn "$udid" log show --start "$since" --style compact \
  --predicate 'subsystem == "org.setdef.fledge.spike"' > "$log.oslog" 2>&1 || true
echo "--- stdout/stderr (simctl launch --console-pty)"; cat "$log.stdout"
echo "--- unified log (os_log, subsystem org.setdef.fledge.spike), first lines"; head -20 "$log.oslog"
grep -q 'FLEDGE-SPIKE-OK' "$log.stdout"
grep -q 'FLEDGE-SPIKE-OK' "$log.oslog"
echo "PASS: $want"
