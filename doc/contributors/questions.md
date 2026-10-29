<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. None of these blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## A. An Apple Developer account, for iOS on a real device and App Store review

**Context.** The maintainer said on 2026-10-28: "We should eventually get an Apple Developer account, but I'd like to wait until the last responsible moment." Plan 002's story "Mobile apps from fledge build" reaches that moment for two of its proofs. `fledge build ios` writes an Xcode project that builds unsigned for devices and runs in the iOS Simulator on an iPhone and an iPad in CI (ADR 012). What remains needs a development team to sign with, which only an Apple Developer account gives: running a built app on a real iPhone and iPad, where Apple's sandbox differs from the Simulator's (no `fork`, a read-only bundle; ADR 011, section 6), and submitting one to App Review, which judges Fledge's runtime, its privacy manifest, and its interpreter (guidelines 2.5.2 and 4.2.6). Each developer signs and submits their own app; the account would be setdef's, for Fledge's own proof.

**Default.** Work proceeds without one: iOS is proven in the Simulator and by an unsigned device build in CI, and ADR 012 and Plan 002 list the device run and App Review as not yet proven. Nothing else in Plan 002 waits on it.

**To reverse.** Get the account (and, for CI, a device or a device cloud); then a story adds a signed device run and a TestFlight submission of `examples/hello` and `examples/mobile_app`.
