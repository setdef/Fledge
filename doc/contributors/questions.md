<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. Each question stands alone: it states everything needed to answer it, with no file to open first. None of them blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## C. What must be proven, or available, before 1.0.0? (open, no deadline)

You have not decided this, and nothing waits on it. It is here so that it stays on your list.

**What you said.** There is no 1.0 until "at least some of these things are proven": a game on a real iPhone or iPad with App Review, a signing chain from a real Apple or Microsoft certificate, and Android's arm64-v8a build running. On 2026-11-05 you also decided to pay for the accounts and certificates the stores need.

**Where they stand on 2026-11-06.**

- *A real iPhone and iPad:* proven. Dot Popper ran on your iPad Pro and on an iPhone 13 mini, signed with a free Personal Team. App Review is not done: it needs your Apple Developer Program enrollment, US$99 a year.
- *Android on arm64:* proven. You played Dot Popper on your OnePlus Nord N30 5G (Android 14), from an APK that Fledge v0.5.1 built.
- *A real signing chain:* not proven. The Apple enrollment gives a Developer ID certificate, which Fledge signs with already, though it does not notarize yet. Windows needs a trusted code-signing certificate, bought separately.

**How people get apps.** You have not said whether any of these must come before 1.0.0. Each adds to 1.x without breaking it, because `fledge.yml` and the command refuse what they do not know, so none forces a change to what 1.0 freezes.

- *App stores, for windowed apps:* the App Store and Google Play take the Xcode and Gradle projects Fledge writes; the Microsoft Store takes Fledge's setup program once it is signed with a trusted certificate; the Mac App Store needs a sandboxed mode and a `.pkg`, which Fledge does not build. No Fledge app has been through any store's review yet.
- *Package managers, for console apps:* Scoop, a Homebrew tap, and winget work today with a file the developer writes, and Fledge's guide gives each one; Windows apps work through winget's links, which CI checks. Homebrew's official casks need notarization.
- *Self-updating:* nothing is built.

**Default.** 1.0.0 waits for nothing more than the two proofs already done. The signing chain, stores, package managers, and self-updating are named in the README as not yet proven or not offered.

**To reverse.** Say what else blocks 1.0.0, such as App Review or a real signing chain. Agents then change the "1.0" story in Plan 003.
