<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. Each question stands alone: it states everything needed to answer it, with no file to open first. None of them blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## C. Which account-blocked tests must pass before 1.0.0 is tagged? (open, no deadline)

Nothing waits on this. It is here so that it stays on your list.

**What you said.** On 2026-11-02: there is no 1.0 until "at least some of these things are proven": a game on a real iPhone or iPad with App Review, a signing chain from a real Apple or Microsoft certificate, and Android's arm64-v8a build running. On 2026-11-04: "I've decided to pay Apple, Microsoft, Google, whoever I need." On 2026-11-08: "I want this 1.0.0-ready pending only my manual testing (or the testing I need to prompt you to do) that is blocked on my developer accounts." On 2026-11-19: "My testing happens _on_ the release candidate, which, if it all passes, will be simply made into 1.0.0."

So agents are finishing everything for 1.0.0 that your accounts do not block. What is left open is which of the account-blocked tests must pass before you tag 1.0.0.

**Where they stand on 2026-11-08.**

- *A real iPhone and iPad:* proven. Dot Popper ran on your iPad Pro and on an iPhone 12 mini, signed with a free Personal Team. App Review is not done: it needs your Apple Developer Program enrollment, US$99 a year, which is under way and waits on your review of Apple's agreement and on a D-U-N-S number.
- *Android on arm64:* proven on a device. You played Dot Popper on your OnePlus Nord N30 5G (Android 14), from an APK that Fledge v0.5.1 built. No CI runner can run an arm64-v8a emulator with hardware acceleration, so CI still checks only x86-64 Android.
- *A real signing chain:* built, and not proven with a real account. Fledge v0.9.0 signs a Mac app with your Developer ID and notarizes it (`--sign IDENTITY --notarize PROFILE`), and signs a Windows app with `signtool` or a command of your own (`--sign-command`, for a cloud or hardware signer such as Azure Artifact Signing). CI proves them only against stand-ins for Apple's notary service and for a signer, with a self-signed identity. The first run with a real Developer ID and a real Windows certificate is yours, and `doc/contributors/signing-test.md` walks you through it. Windows needs a trusted code-signing certificate or a signing service, bought separately.

**How people get apps.** You have not said whether any of these must come before 1.0.0. Each adds to 1.x without breaking it, because `fledge.yml` and the command refuse what they do not know, so none forces a change to what 1.0 freezes.

- *App stores, for windowed apps:* the App Store and Google Play take the Xcode and Gradle projects Fledge writes; the Microsoft Store takes Fledge's setup program once it is signed with a trusted certificate; the Mac App Store needs a sandboxed mode and a `.pkg`, which Fledge does not build. No Fledge app has been through any store's review yet.
- *Package managers, for console apps:* Scoop, a Homebrew tap, and winget work today with a file the developer writes, and Fledge's guide gives each one; Windows apps work through winget's links, which CI checks. Homebrew's official casks need notarization, which Fledge now does.
- *Self-updating:* nothing is built.

**Your list.** Agents keep a checklist of every account-blocked test, with what each needs, how to run it, and what counts as passing, in `doc/contributors/account-tests.md`. On 2026-11-08 you said: "Keep a list of account-block tests current and clear for me to work through myself; I may decide at some point which ones I want to keep blocking 1.0.0 and which ones I don't." Each entry there reads "Blocks 1.0.0? not decided" until you change it.

**Default.** Agents finish everything for 1.0.0 that your accounts do not block, tag no `v1.0.0` until you say your testing is done, and name no account-blocked test as a requirement until you do. The signing chain, App Review, stores, package managers, and self-updating are named in the README as not yet proven or not offered.

**To reverse.** Name the tests that must pass before 1.0.0, such as App Review, a notarized app that opens on a fresh Mac, or a setup program signed through a real chain. Agents then change the "1.0" story in Plan 003 and the checklist in `doc/contributors/releasing-1.0.md` to say that the release waits for them.

## F. Where may Fledge keep a pinned copy of what Gradle downloads, so that CI never asks Maven Central? (open, no deadline)

Nothing waits on this. It decides whether one kind of red CI run can be ruled out, or only made rare.

**What happens.** An Android app is built by Gradle, which downloads the Android Gradle plugin and everything it needs, a few hundred files and about 240 MB, from Maven Central and Google's Maven repository. Maven Central limits how much it serves to addresses that download a great deal, and GitHub's hosted runners share addresses. From 13 to 19 November 2026, nine full CI runs on `trunk` went red because Central answered a runner with "429 Too Many Requests", or with "not found" for files it holds; no commit was at fault in any of them, and one of them was a release's run.

**What agents did.** Every CI job that runs Gradle now keeps those downloads in GitHub's Actions cache, and when the exact set is missing it starts from the nearest earlier one, so Gradle asks Central only for what changed. That leaves two cases that still ask Central for everything, and go red if it refuses the runner: the first run after the plugin's version is moved, and a job whose set has left the cache. GitHub removes a cache entry that no run has used for seven days, and evicts the least recently used entries once a repository's caches pass 10 GB. The repository's caches were at 10.5 GB on 2026-11-20, and should be near 7 GB after that night's changes.

**What would close it.** A copy of each set that nothing evicts, pinned by SHA-256 like every other download Fledge's CI makes, which Gradle reads as a read-only cache of dependencies (its `GRADLE_RO_DEP_CACHE`). An agent cannot choose where that copy lives:

- *As a file on a GitHub Release of Fledge,* beside the runtimes, or on a release of its own that no app developer is sent to. It is the same host and account Fledge uses now, and costs nothing. But Fledge would then be publishing other projects' files itself: the Android Gradle plugin and its dependencies, most under Apache-2.0, each with its own notice. Your rule is that every line Fledge publishes is clearly Fledge's or clearly attributed, and whether Fledge should republish a build tool's files at all, for its own CI's sake, is yours to say.
- *As more Actions cache storage,* which GitHub sells above the 10 GB a repository gets. On 2026-11-04 you said: "I've decided to pay Apple, Microsoft, Google, whoever I need." This would be paying GitHub, and it only makes eviction rarer; an unused entry still goes after seven days.
- *On another host.* On 2026-11-04 you said: "Absolutely not. If you want a second host, you come to me asking (optionally with suggestions)." No agent is asking for one here; it is listed so the choice is whole.

**Default.** Nothing more is stored anywhere. CI keeps the cache as it is, a run that Central refuses in one of the two remaining cases is run again, and the design document for phone projects says so.

**To reverse.** Say "publish the set on a release" (and whether beside the runtimes or apart from them), or "pay for more cache". Agents then build that, with the notices the files need, and remove this question.
