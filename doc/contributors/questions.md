<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. Each question stands alone: it states everything needed to answer it, with no file to open first. None of them blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## C. Which account-blocked tests must pass before 1.0.0 is tagged? (open, no deadline)

Nothing waits on this. It is here so that it stays on your list.

**What you said.** On 2026-11-02: there is no 1.0 until "at least some of these things are proven": a game on a real iPhone or iPad with App Review, a signing chain from a real Apple or Microsoft certificate, and Android's arm64-v8a build running. On 2026-11-04: "I've decided to pay Apple, Microsoft, Google, whoever I need." On 2026-11-08: "I want this 1.0.0-ready pending only my manual testing (or the testing I need to prompt you to do) that is blocked on my developer accounts."

So agents are finishing everything for 1.0.0 that your accounts do not block. What is left open is which of the account-blocked tests must pass before you tag 1.0.0.

**Where they stand on 2026-11-08.**

- *A real iPhone and iPad:* proven. Dot Popper ran on your iPad Pro and on an iPhone 13 mini, signed with a free Personal Team. App Review is not done: it needs your Apple Developer Program enrollment, US$99 a year, which is under way and waits on your review of Apple's agreement and on a D-U-N-S number.
- *Android on arm64:* proven on a device. You played Dot Popper on your OnePlus Nord N30 5G (Android 14), from an APK that Fledge v0.5.1 built. No CI runner can run an arm64-v8a emulator with hardware acceleration, so CI still checks only x86-64 Android.
- *A real signing chain:* built, and not proven with a real account. Fledge v0.9.0 signs a Mac app with your Developer ID and notarizes it (`--sign IDENTITY --notarize PROFILE`), and signs a Windows app with `signtool` or a command of your own (`--sign-command`, for a cloud or hardware signer such as Azure Artifact Signing). CI proves them only against stand-ins for Apple's notary service and for a signer, with a self-signed identity. The first run with a real Developer ID and a real Windows certificate is yours, and `doc/contributors/signing-test.md` walks you through it. Windows needs a trusted code-signing certificate or a signing service, bought separately.

**How people get apps.** You have not said whether any of these must come before 1.0.0. Each adds to 1.x without breaking it, because `fledge.yml` and the command refuse what they do not know, so none forces a change to what 1.0 freezes.

- *App stores, for windowed apps:* the App Store and Google Play take the Xcode and Gradle projects Fledge writes; the Microsoft Store takes Fledge's setup program once it is signed with a trusted certificate; the Mac App Store needs a sandboxed mode and a `.pkg`, which Fledge does not build. No Fledge app has been through any store's review yet.
- *Package managers, for console apps:* Scoop, a Homebrew tap, and winget work today with a file the developer writes, and Fledge's guide gives each one; Windows apps work through winget's links, which CI checks. Homebrew's official casks need notarization, which Fledge now does.
- *Self-updating:* nothing is built.

**Your list.** Agents keep a checklist of every account-blocked test, with what each needs, how to run it, and what counts as passing, in `doc/contributors/account-tests.md`. On 2026-11-08 you said: "Keep a list of account-block tests current and clear for me to work through myself; I may decide at some point which ones I want to keep blocking 1.0.0 and which ones I don't." Each entry there reads "Blocks 1.0.0? not decided" until you change it.

**Default.** Agents finish everything for 1.0.0 that your accounts do not block, tag no `v1.0.0` until you say your testing is done, and name no account-blocked test as a requirement until you do. The signing chain, App Review, stores, package managers, and self-updating are named in the README as not yet proven or not offered.

**To reverse.** Name the tests that must pass before 1.0.0, such as App Review, a notarized app that opens on a fresh Mac, or a setup program signed through a real chain. Agents then change the "1.0" story in Plan 003 and the checklist in `doc/contributors/releasing-1.0.md` to say that the release waits for them.
