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

## H. Should Fledge build apps for Intel Macs? (open, no deadline)

Nothing waits on this.

**Context.** Fledge builds Mac apps for Apple silicon only, and the README says so: "Fledge builds nothing for Intel Macs". An app built for Apple silicon does not run on an Intel Mac. The question came up on 2026-11-22 because the maintainer has two Intel Macs he would like to put to use as build machines, and the program that runs on a build machine is a Fledge app. Of the cost he said "this is kinda damning" when told that Apple stopped selling Intel Macs in 2023 and has announced macOS 26 as the last release that runs on them.

**What it would take.** A pinned Ruby for Intel macOS (rv-ruby publishes one; the builds mise downloads do not), the launcher and runtime built for it, a job in CI that builds, tests, and delivers on an Intel macOS runner, and that runtime published with every release from then on. An agent estimated one to two days of agents' work. The lasting cost is the runner: GitHub is retiring its Intel macOS runners, and once they are gone only a Mac of the maintainer's own could prove an Intel release.

**Default.** No. Fledge stays on Apple silicon, and nothing is built for Intel Macs. The agents recommend this default: nobody who builds apps has asked, the computers it serves get no new macOS, and each release would carry another runtime to build and prove.

**To reverse.** Say "support Intel Macs", and which macOS is the oldest they must run. Agents then add the platform as `x86_64-darwin`, with the README and the compatibility table changed to match.

## I. If no maintained project's Ruby runs on older Linux, should Fledge build its own? (open, no deadline)

Nothing waits on this, and it may never need an answer.

**Context.** Until 2026-11-22, an app built by Fledge for mainstream Linux needed glibc 2.39 or newer, which is Ubuntu 24.04, Debian 13, and recent Fedora, and did not run on Ubuntu 22.04, Debian 12, RHEL 8 or 9 and their clones, or Amazon Linux 2023. That floor came from the Ruby Fledge took prebuilt from rv-ruby, which is compiled on Ubuntu 24.04. You accepted it on 2026-10-26: "2.39 is fine". On 2026-11-22, shown the list of systems it leaves out, you said "Oof."

**What was done.** The prebuilt Rubies that mise downloads (jdx/ruby, a fork of rv-ruby) are compiled for glibc 2.17. Fledge's mainstream Linux runtime now takes its Ruby from there, and compiles its own small parts on AlmaLinux 8, so an app needs glibc 2.28 or newer, which covers every system named above, without Fledge compiling Ruby itself.

**The question.** Only if that stops working (the other project's Ruby stops passing Fledge's checks, or stops being published): should Fledge then compile its own Ruby for mainstream Linux, as it already does for Alpine Linux and for phones, to keep the lower floor? It would mean Fledge maintains a build of Ruby on its most used Linux platforms, and that keeping its built-in libraries (OpenSSL and the others) current becomes Fledge's own work, which the automation you asked for on 2026-11-22 would have to cover.

**Default.** No. If the other project's Ruby can no longer be used, Fledge goes back to rv-ruby and the floor back to glibc 2.39, by your words of 2026-10-26, and agents tell you.

**To reverse.** Say "build our own Ruby for Linux if you have to". Agents then do that when the need arises, with the lowest floor the tools allow.

## J. On a Mac, which platform should an app's Ruby say it is? (open; the macOS Ruby cannot be updated unattended until answered)

**Context.** Ruby names its platform after the macOS it was built on: `arm64-darwin23` if built on macOS 14, `arm64-darwin24` on macOS 15. Fledge takes its macOS Ruby prebuilt from rv-ruby, and the build it pins says `arm64-darwin23`. rv-ruby's release of 2026-11-19 was built on macOS 15 and says `arm64-darwin24`; it is otherwise the same Ruby, and still runs on macOS 14.

Bundler compares that name with the platforms a project's `Gemfile.lock` lists, and darwin versions must be equal. A lockfile that lists `arm64-darwin` (no number, which the README tells developers to add) or `ruby` fits any of them. A lockfile that lists only `arm64-darwin-23`, which is what `bundle install` writes for a developer whose own Ruby was built on macOS 14, fits today's runtime and would not fit the newer one: `fledge build` would stop and tell them to run `bundle lock --add-platform arm64-darwin`. The reverse is true today for a developer on macOS 15, whose lockfile says `arm64-darwin-24`.

So moving to rv-ruby's newer build can make `fledge build` refuse a lockfile it accepted the day before. You asked on 2026-11-22 that a newer upstream release become a Fledge release with nobody in the loop, and after 1.0 a release that does this could not be a patch or a minor one.

**The question.** Choose one:

1. **The app's Ruby says `arm64-darwin`, with no number,** whatever macOS rv-ruby built it on, as Fledge's iOS Ruby already does. Every lockfile fits, on every release, and the name never changes again. The cost is a difference from `ruby main.rb`: `RUBY_PLATFORM` and `RbConfig`'s names would read `arm64-darwin` where the developer's own Ruby reads `arm64-darwin23` or `24`, and the runtime's folders are renamed to match. The agents recommend this one: the number records where someone else built Ruby, not anything about the person's Mac, and a difference that keeps every developer's lockfile working is a cheaper one than a build that refuses them once a year.
2. **The name follows rv-ruby's build.** No difference from that Ruby. Each time rv-ruby builds on a newer macOS, developers who list only the old number are refused at build time, with the one-line fix. Such a move would be a breaking release and would wait for a person.
3. **Stay as it is.** The pin automation stops on such a release and calls a person, who decides then.

**Default.** 3. Agents change nothing: the macOS Ruby stays on the build Fledge pins, and the automation reports that rv-ruby's newer build names another platform. Security fixes in the macOS Ruby wait until you answer.

**To reverse.** Say "1" or "2". Agents then build it, with the documents and the parity record changed to match.

