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

## K. May Fledge publish copies of the files Gradle downloads, so that CI never needs Maven Central? (open, no deadline)

Nothing waits on this. It decides whether a move of the Android build tools' pins can stall on another company's servers.

**Context.** To build an Android app, Gradle downloads Google's Android build plugin and about 160 other Java libraries from Maven Central and Google's repository. Maven Central sometimes refuses GitHub's runners, which share their internet addresses with everyone else's, for minutes or hours at a time: nine of Fledge's full CI runs failed that way from 13 to 19 November. CI keeps what Gradle downloaded in GitHub's cache, but the first run after the automation moves the plugin's or Gradle's version has nothing kept, because nothing has downloaded the new version yet. You asked on 2026-11-22 that a new upstream release become a Fledge release with nobody pinged: "I don't want to be pinged, I want Fledge to just... get a new release. (on the happy path)". A refusal on that first run fails the move, and the automation then pings you.

**The question.** May Fledge publish, on its own GitHub Releases, as a pre-release that app developers are never sent to, an archive of exactly the files Gradle downloaded, unmodified, with each project's notice and license? CI would then take them from there and never ask Maven Central. Only Fledge's CI would read the archive. A developer's own build asks the repositories as it always has. It needs no new host or account: of a second host you said "If you want a second host, you come to me asking" (2026-11-04), and this uses the one Fledge already has. It does mean Fledge redistributing other projects' software, and AGENTS.md says: "Every line must be clearly Fledge's or clearly attributed."

**What the licenses ask.** Most of the files are under permissive licenses that ask only that the license and notices go with the copy: Apache-2.0, MIT, BSD-3-Clause, the Eclipse Distribution License, Bouncy Castle's license, and JDOM's (its text adds that the name "JDOM" not be used to promote another product). The rest, read from each license's own text:
- **MPL 1.1** (juniversalchardet, one library). Section 3.6 allows a copy of the compiled library only with a notice "stating that the Source Code version of the Covered Code is available under the terms of this License", saying how and where. Fledge would publish that library's source beside the archive, as it already does for its LGPL libraries.
- **EPL 2.0, or GPL 2.0 with the Classpath Exception** (some Java EE and JUnit project files). Every file under these is a Maven POM: an XML file that describes a project and holds no program. A POM is its own source, so under EPL 2.0 Fledge would include the license with it (section 3.2) and keep its notices (section 3.3). The GPL option is not needed.
- **LGPL 2.1 or Apache-2.0** (JNA): Fledge would take the Apache-2.0 option.
- **No license stated** (two Sonatype parent POMs, XML files with no program in them), and kxml2, whose POM says "Public Domain" and "BSD style" but links to a page that no longer exists. Neither license text was found, so both are unverified. A third-party file whose license cannot be shown would be left out, which might make the archive incomplete.

That list comes from one partial download, of the set for the runtime's own Android library only: that build stopped partway, most likely on a refused download, since the same build from nothing then finished, with 325 files where the first had 298. The full sets, one for each system CI builds Android apps on, may hold more. The tool that makes a set would refuse a file whose license it does not know, and ask you.

**What it buys.** A move of the Android plugin's or Gradle's pin could never stall on Maven Central, and neither could any other run.

**Default.** No copies are published. Instead, every CI job that runs Gradle retries a refused download patiently, as Gradle itself allows: seven tries, waiting from 10 seconds to more than 5 minutes between them, ten and a half minutes in all. Gradle retries only an answer that says the server is busy or failing, or a lost connection, so a build that fails for its own reasons is not slowed; it cannot retry Central's other refusal, answering "not found" for files it has, since that looks like a library that does not exist. A refusal of either kind that outlasts this still fails that day's move, and the automation pings you as it does today. It cannot report the move as "held" instead, because a hold is something a person sets on a pin ahead of time, not something a failed proof can show. The next day's watch tries the move again.

**To reverse.** Say "publish the Gradle sets", and say whether a library under MPL 1.1, with its source published beside it, may be among them. Agents then build the sets as `doc/contributors/design/phone-projects.md`, "The pinned sets", describes.

