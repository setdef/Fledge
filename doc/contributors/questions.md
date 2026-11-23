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

## L. Should Fledge ask rv-ruby to build its Alpine Linux Rubies the way its other Linux Rubies are built? (open, no deadline)

Nothing waits on this.

**Context.** Fledge still compiles its own Ruby for Alpine Linux (musl). rv-ruby, the project whose prebuilt Ruby Fledge's macOS apps used until 2026-11-22, does publish Alpine Linux Rubies for the version Fledge pins, 4.1.0-preview1, on Intel and ARM. On 2026-11-22, told that, you said "Whenever we're adding a platform, that should be the first thing we check before building our own." Agents checked both of those files the same day. rv-ruby builds them differently from its other Linux Rubies: every built-in library that is compiled (OpenSSL, JSON, YAML, sockets, and the rest) is baked into rv-ruby's own `ruby` program, and the library Fledge's launcher links Ruby from has none of them. A Fledge app made from it could not load any of them. The files also carry no list of the third-party code inside them, which Fledge's license check needs. So Fledge keeps its own build for now. It costs Fledge a compile of Ruby, OpenSSL, and three smaller libraries each time it builds an Alpine runtime, a small edit to Ruby's source until Ruby 4.1.0, and Rust, Perl, and the few other Alpine packages only that compile needs, all pinned and moved on purpose. Apps would still be built and tested in Alpine either way. You said on 2026-10-28 that "Code is a liability".

**The question.** Should someone ask rv-ruby to build its Alpine Linux Rubies with each compiled library as a separate file, as its other Linux Rubies already are, and to ship the license list with them? If rv-ruby did, Fledge could take its Alpine Ruby from there and delete its own build. Asking means an issue or pull request on rv-ruby's GitHub project, posted from your account, which agents do not do.

**Default.** No one asks. Fledge keeps building Alpine Linux's Ruby, and agents check rv-ruby's Alpine files again when Ruby 4.1.0 is released.

**To reverse.** Say "ask rv-ruby". Agents then write the issue for you to post, with what they measured and the one build option that makes the difference.

## M. Which version number should the release that serves as the candidate carry? (open, no deadline)

Nothing waits on this.

**Context.** The candidate for 1.0.0 is a 0.x release that has everything 1.0.0 will, and your testing is done on it. The newest release is v0.17.0. The release tooling picks the next number for any release by Fledge's rule for 0.x (the last number for fixes and additions that break no build, the middle number for a change that can break one), and it never picks the candidate's number: Fledge's release design says the candidate's middle number is a person's to name. So someone has to name it, or say the tooling's number will do.

**The question.** Do you want to name the candidate's version, and if so, what is it? Or may the candidate carry whatever number the tooling gives the release, with its release notes saying that it is the candidate?

**Default.** The candidate carries the tooling's next 0.x number, as any release does, and its release notes say it is the candidate for 1.0.0.

**To reverse.** Name the number. Agents then give that number to the release commit and say in the notes that it is the candidate.

## N. Should the Rooibos example stay in the repository while its gem cannot be built for the runtimes' Ruby? (open, no deadline)

Nothing waits on this.

**Context.** `examples/rooibos_console` is a small terminal app built on Rooibos, one of the three framework wrappers (Lota, Tokra, Rooibos) that Fledge serves. Built on the Ruby the runtimes carry now, 4.1.0-preview1, it does not build: `fledge build` stops with "gem ratatui_ruby-1.5.2's extension did not compile for arm64-darwin". The gem's precompiled builds say they need a Ruby below 4.1, so Bundler takes its source, and the source does not compile against Ruby 4.1. Another project that locks the same gem reports that the cause is in that gem's own dependencies, which Fledge has not checked itself (issue 44, which also records that no check builds the example). No workflow, test, or task builds the example today.

**The question.** Should the example stay in the repository, marked as waiting on its gem and left out of the checks until the gem supports the Ruby the runtimes carry, or be removed until then?

**Default.** It stays, with its reason written beside it. When the check that builds every example is written (issue 44), the example is named in that check's list of what it leaves out, with the reason. It is built again once the gem supports the runtimes' Ruby.

**To reverse.** Say "remove it". Agents then delete the folder and note the reason in `doc/gems.md`, and bring it back when the gem builds.

## O. Does `examples/hello` stay under `examples/`? (open, no deadline)

Nothing waits on this.

**Context.** A folder under `examples/` is meant to be a small real app that does something a person would use, and an app that only starts, reports, and exits is meant to be a fixture under `test/fixtures/`. `examples/hello` is four lines of program, and its own comment says it "greets you and exits". The README presents it as the smallest app to start from, and most workflows build it. Issue 58 lists nine other folders under `examples/` that are fixtures by their own description and should move; it says of `hello` that whether it stays is not decided there.

**The question.** Does `hello` stay under `examples/` as the one deliberate exception to that rule, or move to `test/fixtures/` with the others?

**Default.** It stays, and the contributor guide says it is the one exception and why: a developer wants the smallest app to start from, and the README sends them there.

**To reverse.** Say "move it". Agents then move it, update the README, the workflows, and the documents that name it, and point the README's starting place at `libui_app` or another example.

## P. Should Fledge ship one small real phone app as an example? (open, no deadline)

Nothing waits on this.

**Context.** Every phone folder under `examples/` describes itself as proving something ("The app that proves the ffi gem on iOS, iPadOS, and Android", and so on; issue 58 lists them). Once those move to `test/fixtures/`, `examples/` holds no phone app at all. The guide for phones, `doc/phones.md`, shows a developer the steps.

**The question.** Should Fledge have one small real phone app under `examples/`, a program a person would use on a phone, and if so, what kind of app should it be?

**Default.** No such app is made. `doc/phones.md` keeps showing a developer the steps.

**To reverse.** Say "make one", and what kind (a game, a tool, or something else). Agents then build it as a small real app, with its own check.

## Q. Which of the reports owed to other projects do you want made, and from which account? (open, no deadline)

Nothing waits on this.

**Context.** Four open issues are labelled `upstream`: three in the milestone "1.0.0 release candidate", and 45 outside it, since the candidate does not wait for Ruby 4.1.0. Each ends with whose fault it is, and each says that whether to report it to that project is yours to decide: 37 (Rust gems built on magnus 0.9 do not compile on Windows against Ruby 4.1's 64-bit length type), 38 (jdx/ruby sets no deployment target for macOS, so the floor of Fledge's Mac runtime is the CI runner's SDK), 45 (Ruby 4.1.0 is not released, and the runtimes carry its first preview), and 51 (sqlite3 does not compile on Windows on ARM64). Fledge's rules say an agent posts nothing on another project's tracker, and that reporting is yours.

**The question.** Which of these, if any, do you want reported to the project at fault, and from which account?

**Default.** None is reported. Each stays an issue saying whose fault it is, and Fledge's own part of each is done or tracked in that issue.

**To reverse.** Name the issues. Agents then write each report for you to post from your account.

## R. Should the authorship of past commits be rewritten, and when? (open, no deadline)

Nothing waits on this.

**Context.** Commits made by agents are now authored as "Kerrick's AI Agent(s) <ai@setdef.com>". Every earlier commit carries your own name, though Fledge's rules say everything in it was built by agents. On 2026-10-26 you answered a question about the provenance statement with "None at all, for now. I'll tackle Provenance before releasing 1.0." When this came up in conversation you asked: "Perhaps right before 1.0.0 and before it goes to rubygems.org for the first time?" That was a question, not a decision. Rewriting authorship changes the ID of every commit from the first one changed onward. Fledge's rules allow a force-push only with your authorization and only for commits not yet tagged or released, and every release so far is tagged and has a GitHub Release, whose runtimes' notices link to files there. The orchestrating agent's view was that, if it is done, it be done before the candidate is cut and not between the candidate and 1.0.0, because the candidate is what is tested and a rewrite changes every ID.

**The question.** Do you want the authorship of past commits rewritten; if so, when; and what should become of the existing tags and releases (rewritten to match, or left pointing at the old commits)?

**Default.** Nothing is rewritten, and no `.mailmap` is added. History stays as it is until you say.

**To reverse.** Say "rewrite", and when. Agents then prepare the rewrite and the plan for the tags and releases, and you authorize the force-push.

## S. Is the C locale's difference from `ruby main.rb` still accepted for the candidate? (open, no deadline)

Nothing waits on this.

**Context.** With no locale set, or `LANG=C`, plain `ruby` reads and writes text as US-ASCII. A Fledge app's launcher turns that into UTF-8, so the three default encodings differ from `ruby main.rb` in that one case. It does so because an app started with no locale (a phone starts every app that way) would otherwise fail on any path that is not ASCII. On 2026-11-03 you wrote: "I can buy that for now, but will easily be swayed by the first app dev who gets upset by the deviation. And we shouldn't be cagey about it or hide it." Fledge's documents for developers state the difference, and say it stands until an app developer reports it as a surprise.

**The question.** Is that difference still accepted for the candidate for 1.0.0, or do you want it removed first, so that an app in a C locale sees US-ASCII as under plain Ruby?

**Default.** It is accepted, and stays documented as it is.

**To reverse.** Say "remove it". Agents then make the launcher leave the locale alone, drop the tests and the justified entries that expect UTF-8 in a C locale, and record the change in the changelog as a break.
