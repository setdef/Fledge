<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Maintainer's Decisions

This file records what the maintainer has said, word for word, and nothing else. It is the source of truth for "what the maintainer decided." Everything else in this repository (the ADRs, the plans, the help header, the error messages, the layouts, this file's notes) was written by agents, and agents may change it, as long as it stays true to what is quoted here (AGENTS.md, Provenance).

Each quotation is followed by a note, written by an agent, of what it governs and where it is applied. When a quotation and a note disagree, the quotation wins. When a quotation seems to conflict with another, or is ambiguous, ask in `questions.md`; never guess.

## From the original session

The project was started with these directions, given in prose rather than as a numbered list. They are quoted as the orchestrating agent relayed them from that session.

> Fledge is requested.

*Governs:* how every piece of work here comes to exist, and the `Provenance: requested` trailer on every commit. *Applied in:* AGENTS.md, Provenance.

> Agents may push to trunk.

*Governs:* where agents put their work. *Applied in:* AGENTS.md, Committing. Extended by decision 6 below.

> Never publish to RubyGems.org.

*Governs:* the gem's distribution, forever. *Applied in:* AGENTS.md, Releasing; `fledge.gemspec`'s `allowed_push_host`; `doc/contributors/design/releases.md`, "Where releases are".

> The walking skeleton must walk on macOS, Windows, and Linux.

*Governs:* the scope of Plan 001 and the Delivery jobs. *Applied in:* Plan 001; `.github/workflows/ci.yml`.

> High quality, tests, linters.

*Governs:* the gate and how work is tested. *Applied in:* AGENTS.md, How to work, Commands, and Definition of done.

## 2026-10-26

Answers to the numbered entries of an earlier `questions.md`. Each answer names, in brackets, what the entry asked when the answer alone does not say.

> 2. What are the other options? [re: "an app is a folder with a main.rb" — still open]

*Governs:* nothing yet; the maintainer asked a question back. *Applied in:* `questions.md`, entry A. The current layout (a folder with a `main.rb`) stays until it is answered.

> 3. None at all, for now. I'll tackle Provenance before releasing 1.0. [re: the provenance statement under exe/fledge's help header]

*Governs:* `exe/fledge` carries no provenance statement. Commits still carry the `Provenance: requested` trailer, which is AGENTS.md's process, not a statement in the product. *Applied in:* `exe/fledge`; `test/cli_test.rb`.

> 4. What is the GNU standard? What is the Unix standard? What would Windows users expect? [re: -V and bare-fledge behavior]

*Governs:* the maintainer asked that agents follow the standards rather than ask (see decision 16). *Applied in:* ADR 002 (`-h`, `-?`, `--help`, `-v`, `--version`; exit status 2 for usage errors).

> 5. You invented the help header, so that's a problem you created. My instinct is to use the app's primary class/module's name, like MyCoolApp. [re: NAME in dist/NAME-PLATFORM — depends on #2, still open]

*Governs:* where NAME comes from, once decision 2 is settled. *Applied in:* `questions.md`, entry B. NAME stays the app folder's name until then.

> 6. Before the release of 1.0, you may push to trunk and you may create and push tags and you may create github releases, but you may not release to rubygems.

*Governs:* what agents may publish before 1.0. *Applied in:* AGENTS.md, Committing and Releasing; `.github/workflows/release.yml`.

> 7. 2.39 is fine, and even newer may be fine if there becomes good reason to raise the floor.

*Governs:* the oldest glibc a Linux app runs on. *Applied in:* ADR 035; `doc/contributors/design/releases.md`, "Platform floors".

> 8. Because of what I said re: #1, we must be VERY careful to be able to let app devs _not_ be copyleft-laden when they pay for a commercial license.

*Governs:* the license of everything Fledge itself copies into an app, its runtime: no third-party component may leave an app's developer with copyleft obligations beyond notices. It stands on its own since 2026-11-07, when Fledge itself became MIT ("#1" and the commercial license it names are gone). It does not reach the app's own gems, which the 2026-10-28 reply leaves to the app's developer. *Applied in:* AGENTS.md, Licensing; Plan 002, "Copyleft-free runtimes" and "Tell app developers what they owe, from CI."

> 9. When using fledge, your ruby source code should be able to be identical to how it was without Fledge, so the things you had to `require` before you can still need the app dev to `require`, but the things you didn't have to `require` before the app dev still shouldn't have to require.

*Governs:* what a runtime ships and what the launcher does to Ruby's state. *Applied in:* ADR 081 and ADR 085; the parity check (`tasks/parity.rb`, run in CI on every platform); `RuntimeBuilder` keeping every default and bundled gem.

> 10. All the ruby globals should be non-surprising to app devs, for the same motivation as #9.

*Governs:* `$0`, `$LOAD_PATH`, `$LOADED_FEATURES`, and every other global an app sees. *Applied in:* ADR 081; the launcher (no `-I`, no `--yjit`); the parity check.

> 11. I don't understand what I'd be deciding here. [re: restoring the person's own RUBY*/GEM*/BUNDLE* env for child processes — orchestrator is explaining; still open]

*Governs:* nothing yet. *Applied in:* `questions.md`, entry C, which tracks the follow-up. The launcher now restores the person's environment after Ruby boots, as the orchestrating agent directed (ADR 040).

> 12. Many CI platforms only run on musl for Linux, so I'd like to support it eventually, but it's not a blocker to continuing to iterate. It may be a blocker to 1.0 though.

*Governs:* musl Linux targets. *Applied in:* Plan 002, "musl Linux."

> 13. Again, you invented the help header. Recall the difference between what _I've said_ vs. what's on disk. You need _me_ to second-guess _me_, but you don't need _me_ to second-guess _yourself_.

*Governs:* the `fledge build` surface is the agents' to decide. *Applied in:* AGENTS.md, Questions; ADR 002.

> 14. You wrote the ADRs. Recall the difference between what _I've said_ vs. what's on disk. me/me vs. me/yourself

*Governs:* ADR content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions; ADR 014 (how a version pins its runtimes).

> 15. You wrote the plans. Recall the difference between what _I've said_ vs. what's on disk. me/me vs. me/yourself

*Governs:* plan content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions; Plan 001 (what hello prints).

> 16. Why is this something I should decide? Isn't this something where there's prior art or an industry standard we can/should follow?

*Governs:* behavior with prior art or a standard is the agents' to decide, citing it. *Applied in:* AGENTS.md, Questions; ADR 002 (launcher errors follow `ruby:` messages and sysexits.h).

> 17. Ideally, fledge developers should have the option to make it so Windows/macOS don't block the use of the app. But not every app dev will have the done the required ceremony with Microsoft and/or Apple.

*Governs:* code signing and notarization: an option for developers who have the credentials, with unsigned builds still working. *Applied in:* Plan 002, "Signing and notarization."

> 18. Would this affect what shows up in the taskbar? task manager? start menu? desktop icons? app window top-left corner and/or title bar? If so, app devs need to be able to control it.

*Governs:* an app's icon, name, and version information on every OS are the developer's to control. *Applied in:* Plan 002, "App identity."

> 19. I don't understand what I'd be deciding here. [re: RubyInstaller signing key expiry — agents own this]

*Governs:* the RubyInstaller signing key is the agents' to manage. *Applied in:* ADR 035; `doc/contributors/design/runtimes.md`, "The RubyInstaller signing key"; `runtime/sources.yml`.

> 20. Tiny filesize is not a priority; "my ruby code just works" _is_ a (high) priority.

*Governs:* what runtimes prune: only what no running Ruby code can observe. *Applied in:* ADR 085; `RuntimeBuilder::Pruning.prune`.

> 21. I don't understand what I'd be deciding here. [re: Windows console code pages and Ctrl-C — agents own this]

*Governs:* console code pages and Ctrl-C on Windows are the agents' to decide. *Applied in:* ADR 081 (the launcher matches `ruby.exe`, but for the ANSI code page, ADR 070); the parity check's `chcp 437` run; Plan 002, "Ctrl-C and the console."

> 22. I'd like to support Windows on ARM (and Linux on ARM) eventually, but it's not a blocker to continuing to iterate. It may be a blocker to 1.0 though.

*Governs:* ARM targets. Linux on ARM already ships as `aarch64-linux`. *Applied in:* Plan 002, "Windows on ARM."

> 23. Would this require app devs to have a bunch of `if`s or polymorphic objects used throughout their app to handle the difference? [re: Windows ruby\ vs Unix lib/ layout — answer is no; agents own this]

*Governs:* the internal layout of a runtime is the agents' to decide, as long as app code needs no per-OS branches for it. *Applied in:* ADR 038.

> 24. See #8 [re: GMP being LGPL]

*Governs:* GMP, like every other component of a runtime, falls under decision 8. *Applied in:* Plan 002, "Copyleft-free runtimes."

## 2026-10-26, later

Replies to the orchestrating agent's answers in chat, quoted from the maintainer's messages. The orchestrating agent recorded them, because the maintainer, asked whether it could, said "You may" (2026-10-27). Brackets say what each reply answered.

> 2. Ok.

[re: what the options are besides a folder with a `main.rb`: the orchestrator offered (a) a folder with a `main.rb`; (b) the executable you already run, such as `exe/my_cool_app` or `bin/server`, with the project root where the Gemfile or gemspec is; (c) a configuration file naming the entry point; (d) the gemspec's `executables`. It recommended (b), with configuration only where it's needed, and NAME taken from the project (the gemspec's name or the folder's, camelized, such as `MyCoolApp`), which configuration can override.]

*Governs:* an app's layout and entry point, and, with decision 5, where NAME comes from. *Applied in:* Plan 002, "Ship the executable you already run."

> 4. Ok.

[re: the CLI conventions: `-h`, `-?`, and `--help`, and `-v` and `--version`, print to standard output and exit 0; a usage error prints a short usage to standard error and exits 2.]

*Governs:* the CLI conventions. *Applied in:* ADR 002.

> 11. I think yes?

[re: whether to restore the person's own `RUBYOPT`, `GEM_*`, `BUNDLE_*`, and the rest into `ENV` after Ruby has booted, so the app's `ENV` and its child processes look as they would without Fledge, while the app's own boot stays protected. The orchestrator recommended restoring.]

*Governs:* the environment an app and its child processes see. *Applied in:* ADR 040; `runtime/launcher/unix.c` and `windows.c`; the parity check and Delivery.

> 8 and 24. Remember that LGPL and GPL/AGPL's main differentiator is dynamic linking. Relevant here or not?

> Source offer for... the app? Or the LGPL'ed library? Former won't be liked, latter is fine and normal.

> As long as we're clear about that to app devs, that's great.

[re: libxcrypt on Linux and GMP on Windows, both LGPL. The orchestrator explained that, shipped as separate, replaceable shared libraries, they leave the app proprietary but still require a notice, the library's source or a written offer of it, the ability to replace the library, and app terms that permit reverse engineering for debugging such a replacement (LGPL-2.1 section 6, LGPL-3.0 section 4).]

*Governs:* LGPL components may ship in a runtime only as separate, replaceable shared libraries, never linked statically; Fledge publishes the source of each LGPL library it ships and never requires an app's source or object files; what app developers owe for what Fledge ships is stated to them plainly. These replies govern Fledge's runtimes, not the app's own gems (2026-10-28). *Applied in:* AGENTS.md, Licensing; Plan 002, "Copyleft-free runtimes" and "Tell app developers what they owe."

> "lists, for each platform, everything that..." Better to automate this as part of the DevOps pipeline, yes?

[re: a user-facing page listing, for each platform, every third-party component that ships in an app, its license, and what the app developer must do.]

*Governs:* the component list, license notices, SBOM, and licensing page are generated from each built runtime in CI, behind a license policy gate, never written by hand. *Applied in:* Plan 002, "Tell app developers what they owe."

## 2026-10-27

> We should, if we can, support iOS and iPadOS and Android. Ideally before 1.0 but I could be swayed if it turns out incredibly burdensome.

[re: whether Fledge should target iOS, iPadOS, and Android, which Lota's session raised after the maintainer asked for Lota games on those platforms. The orchestrator had noted that mobile changes Fledge's model: a build step inside Xcode or Gradle, Ruby linked statically with no JIT, and mandatory store rules.]

*Governs:* mobile targets are in scope, aimed at 1.0, unless a spike shows them incredibly burdensome. *Applied in:* Plan 002, "iOS, iPadOS, and Android"; `doc/contributors/research/2026-10-27-mobile.md`.

> Would it be a good idea to move that research somewhere more durable for cross-session reference? Maybe the repo?

*Governs:* research that sessions share lives in the repository, under `doc/contributors/research/`. *Applied in:* `doc/contributors/research/`.

## 2026-10-28

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> Why does it refuse GPL and AGPL gems? That's up to the app dev to decide, not up to Fledge. In fact, why is Fledge taking any kind of opinion at all about what license the gems the app dev uses are under?

[re: the orchestrator's report that `fledge build` refused GPL and AGPL app gems, such as Tokra, allowed LGPL ones only with their source pinned, and refused gems whose binaries had LGPL code linked in statically.]

*Governs:* Fledge takes no position on the licenses of the gems an app depends on — those are the app developer's choice and responsibility; decision 8 and the LGPL replies govern only what Fledge itself puts into apps (its runtime). *Applied in:* ADR 007; AGENTS.md, Licensing; `Fledge::AppGems`, which no longer judges a gem's license or what its compiled files hold, and `Fledge::Linkage`, which checks only that they load; `fledge.yml`, which no longer has `licenses` or `compiled`; the removal of `lib/fledge/compiled_code.yml`, `Fledge::RustCrates`, and `notices/GEMS.txt`; `doc/licensing.md`, "Your app's own gems"; the README; `exe/fledge`'s help; Plan 002; `examples/native_app`, which ships spreadsheet (GPL-3.0), and `examples/nokogiri_app`, which ships for Windows with GNU libiconv linked in.

> We should eventually get an Apple Developer account, but I'd like to wait until the last responsible moment.

[re: whether setdef should get an Apple Developer account, and real devices or a device cloud, which the mobile spike (branch `spike/mobile`, `spike/mobile/FINDINGS.txt`) needs for testing on a real device and for App Store submission; until then testing stays on simulators and emulators. Asked whether to record this, the maintainer said: "Yes, record it in decisions.md."]

*Governs:* agents proceed without an Apple Developer account, and raise it in `questions.md` at the last responsible moment: when a story cannot be done without one. *Applied in:* Plan 002, which marks the stories that reach that moment.

> Code is a liability and we should _not_ have 4k+ lines of things we could use existing tools for.

> We already have to have target-environment-platform machines to compile on, right? If so, what value does cross-platform non-compilation building add?

[re: the orchestrator's report that agents had written about 4,500 lines of Ruby for file formats existing tools handle (a DMG writer, PNG and icon codecs, Windows resource editing, Apple ad-hoc signing, ZIP and tar, SquashFS) and a libfuse shim with a patched AppImage runtime, so that one computer could build every platform, which the maintainer had never asked for. The orchestrator answered that target machines are needed only to compile gems from source, that cross-building adds little because developers need each platform to test and sign on anyway and Tauri, Electron's tooling, and Briefcase build on each OS, and recommended building each target on its own OS with that OS's maintained tools, switching NSIS to LZMA with NSIS's source published, and using the upstream AppImage runtime with its LGPL sources published. The maintainer accepted that recommendation.]

*Governs:* Fledge builds each target on its own OS and uses maintained existing tools rather than code of its own wherever such tools exist; it does not build one platform's app on another. *Applied in:* AGENTS.md, How to work; the story that replaces Fledge's own format writers.

## 2026-11-02

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> We can't spend money on this right now.

[re: `questions.md` entry C, which asked for a device cloud account or an Apple-silicon Mac with hardware virtualization so CI could run Android's arm64-v8a build, after no free GitHub-hosted runner could boot an arm64-v8a emulator.]

*Governs:* agents spend no money on Android's arm64-v8a proof: no device cloud, paid runner, or machine; the story waits for a free way to run it. *Applied in:* Plan 003, "Android on arm64"; ADR 079 and ADR 012; the handoff.

> We can't spend money on this right now.

[re: `questions.md` entries A and B, asked in the same session as the Android answer above: an Apple Developer account for a real iPhone and iPad, App Review, Developer ID, and notarization, and a Windows code signing certificate or Azure Trusted Signing account. The orchestrator had said the Apple account was probably due, and the Windows half was not. The maintainer's words follow the question of whether it was the last responsible moment for each.]

*Governs:* agents open and pay for no account, certificate, device, or service, including Apple's, Microsoft's, and a certificate authority's, until the maintainer says otherwise; the stories that need one wait. *Applied in:* Plan 003, "iOS on a real device, and App Review" and "Notarization and real trust chains"; ADR 012 and ADR 016, which already list what is unproven; the handoff; `questions.md`, entry D.

## 2026-11-02

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> 1. No 1.0 until at least some of these things are proven. But we can go from A.B.C.pre.D to 0.1.0 sem-ver style.
> 2. We really shouldn't have external dependencies on those repos; they are expected to depend upon us, not the other way around.
> 3. Go for .deb

[re: the orchestrator's briefing of what it needed: (1) `questions.md` entry D, whether 1.0 may ship with iOS on a real device and App Review, real signing trust chains, and Android arm64 unproven; (2) two unsent drafts, one asking Rooibos to add CI jobs that build its app with a tagged Fledge and one telling Tokra what Fledge now has, the first of which completed Plan 003's wrapper story only if Rooibos's own CI ran it; (3) optional work, of which the `.deb` installer was the cheapest. The numbering is the maintainer's, answering that briefing.]

*Governs:* 1.0 waits until at least some of the unproven things are proven; releases may move from the `0.0.1.pre.N` form to ordinary 0.MINOR.PATCH versions, beginning with 0.1.0; Fledge depends on no wrapper's repository, wrappers depend on Fledge; a `.deb` installer is built. *Applied in:* Plan 003; the handoff; `questions.md` (entry D removed); the drafts; the next release.

> iPadOS, iOS, and Android are our priorities for 0.2.0.

[re: the Lota session's questions about native extensions on phones, which Plan 003 had placed after 1.0, and the maintainer's wish for Lota games on iPhone, iPad, and Android.]

*Governs:* the work for release 0.2.0 is phones: iPadOS, iOS, and Android, ahead of the stories that wait on money. *Applied in:* Plan 003; the handoff.

## 2026-11-02, later

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> "Never publish to RubyGems.org" was an instruction to agents (for AGENTS.md) not a position the project takes; even when the library is on RubyGems.org I'll continue to make that a human-only activity.

[re: a draft line saying Fledge is "never" installed from RubyGems.org, which followed AGENTS.md's "Never publish to RubyGems.org" as if that rule were a position of the project.]

*Governs:* publishing to RubyGems.org is a human-only activity, whether or not Fledge is on RubyGems.org; the earlier "Never publish to RubyGems.org" and decision 6's "you may not release to rubygems" bind agents and say nothing about the project, so documents for developers do not say Fledge is never published there. *Applied in:* AGENTS.md, Releasing; Plan 003, "1.0"; `doc/contributors/design/releases.md`, "Where releases are".

## 2026-11-02, later again

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> I use three words for how code comes to exist. Code I wrote, I typed by hand, with nothing generated. Code I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I take responsibility for every diff. Code I requested, an agent built with little or no review from me, in the style of a "dark factory."

[re: the orchestrator's question whether it had the maintainer's exact words for written, wrought, and requested, which AGENTS.md, Provenance, had only as an agent's paraphrase, asked while the README's disclosure of how Fledge was made was being written. The maintainer struck "or prose" from the definitions.]

*Governs:* what *written*, *wrought*, and *requested* mean wherever Fledge uses them: the `Provenance:` trailer, AGENTS.md, and the README's disclosure. *Applied in:* AGENTS.md, Provenance; the README.

> I want to get to "I can playtest [a game written in Ruby using Lota] on [an M1 iPad Pro running iPadOS 27] and [a OnePlus Nord N30 5G running Android 13]" as the litmus test for "phones and tablets" (0.2.0).

[re: the orchestrator's report that native gems with C and C++ extensions now run on phones in CI, and its answer that a Lota game could not yet be deployed to a tablet. The maintainer's words named the game and the devices, and then made them specific; the brackets stand for what the maintainer named.]

*Governs:* release 0.2.0 means a Ruby game on Lota can be playtested on an iPad and on an Android phone, built through Fledge. *Applied in:* Plan 003, "A game plays on a tablet and a phone".

> Remember: this entire rule is because _Fledge should never surprise an app dev with how it behaves or causes Ruby or its globals, built-ins, and standard library to behave compared to not using Fledge_.

[re: Design precedence 2, in the discussion of whether a restart through `RbConfig.ruby` in a built app differs from `ruby main.rb`.]

*Governs:* the purpose of Design precedence 2 and of the parity check: a difference between a Fledge app and the same program run without Fledge is a bug unless it is justified and documented. *Applied in:* AGENTS.md, Design precedence 2; ADR 096.

## 2026-11-03

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> Once we hit 1.0.0, we will be releasing via RubyGems (human only), not relying on GitHub Releases and git tags.

[re: the orchestrator's question whether major versions after 1.0 are the maintainer's decision, and its comparison of four ways to release them.]

*Governs:* from 1.0.0, Fledge is also released on RubyGems.org, by a human, so a release can be found there as well as by its git tag and GitHub Release; before 1.0.0 it is found only by its tag and GitHub Release, and nothing is pushed to RubyGems.org (the maintainer's explanation of 2026-11-04, below). Agents prepare a release and never publish it. *Applied in:* Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0"; AGENTS.md, Releasing.

> I can buy that for now, but will easily be swayed by the first app dev who gets upset by the deviation. And we shouldn't be cagey about it or hide it.

[re: the orchestrator's argument for keeping the launcher's turning a bare C locale into a UTF-8 one, a deviation from plain Ruby that Design precedence 1 justifies.]

*Governs:* the locale coercion stays until the first app developer reports it as a surprise, then it is reversed; and any deviation from plain Ruby is documented where app developers read, plainly. *Applied in:* the README; ADR 087; `Parity::JUSTIFIED`.

> A minor release can make additional rubies available, but can only change the defaults' patch versions--unless we abandon the concept of default entirely, and require app devs to specify a version (maybe better?); then it's limited to e.g. generated config files, which can change in a minor version because they don't get re-generated on upgrade.
>
> Ruby doesn't follow SemVer, so 4.1 is expected to have breaking changes from 4.0.
>
> I require a major version bump to drop support for a ruby, or to drop support for an OS "version" (the thing that differentiates MacOS 26 from MacOS 27, not patches etc.).

[re: question A in `questions.md`, whether a 1.x release may change the Ruby inside apps or raise the minimum operating system.]

*Governs:* a minor release may add Rubies and may change only a default Ruby's patch version; the maintainer is open to having no default Ruby, with the app developer naming the version (the orchestrator is to weigh it); generated config files may change in a minor release because an upgrade does not regenerate them; a new Ruby minor is expected to break (Ruby does not follow SemVer); dropping a Ruby, or an operating system version (macOS 26 against 27, not a patch), requires a major version. *Applied in:* ADR 028; ADR 029; ADR 055.

> We'll be reusing the git/ruby version stuff from RatatuiRuby and Rooibos. How tags work (and release branches, backports, etc.) differ before and after 1.0.0.

[re: question B in `questions.md`, whether a release from 1.0 on still gets a git tag.]

*Governs:* Fledge's versioning, tagging, release branches, and backports reuse what RatatuiRuby and Rooibos do, and work differently before 1.0.0 and after it; the tooling itself waits on its extraction (2026-11-07, below). *Applied in:* ADR 028; `doc/contributors/design/releases.md`, "From 1.0: release branches and a human publishing"; Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0".

> winget, Chocolatey, Scoop, brew, apt-get, pacman, dnf, etc. are all very relevant for Ruby console apps.

[re: the orchestrator's relay of a research agent's proposal to record in an ADR that Fledge does not target Flathub or the distributions' archives, and its note that Homebrew, winget, Chocolatey, and Scoop were never researched.]

*Governs:* the package managers (winget, Chocolatey, Scoop, Homebrew, apt-get, pacman, dnf, and others) are in scope for Fledge's console apps; a decision that Fledge does not target them is not made, and none is to be recorded. *Applied in:* `doc/contributors/research/2026-11-04-app-stores.md` (which the package managers extend); Plan 003.

## 2026-11-04

The maintainer wrote this after the orchestrating agent had misread the sentence of 2026-11-03 above ("not relying on GitHub Releases and git tags"). It is quoted in part: the dictionary definitions of "rely", "dependent", "require", and "necessity" that followed it are left out.

> Prior to 1.0.0, this gem would not release via RubyGems by using `gem push`. This is because prior to 1.0.0 I don't know if it'll succeed and I don't want to be a name squatter with a failed project.
> Both before and after 1.0.0, it is expected that, like RatatuiRuby before, all releases will be findable via git tags in the source repos, which automatically become GitHub Relaeses.
> Only before 1.0.0, that is the _only_ way they'll be findable, so releases **rely** on GitHub Releases / git tags.
> After 1.0.0, that is _one way_ they'll be findable, so releases do not **rely** on GitHub Releases / git tags, they can be found another way too.

[re: the orchestrator's account of what the sentence of 2026-11-03 meant, and its design of several gem names that carried Fledge's runtimes.]

*Governs:* nothing is pushed to RubyGems.org before 1.0.0; every release, before and after, has its git tag and the GitHub Release made from it; from 1.0.0 a release is also on RubyGems.org, and "not relying" means only that. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`, "Where releases are" and "From 1.0: release branches and a human publishing"; `doc/contributors/design/public-interface.md`, "Frozen for 1.x"; Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0".

> Absolutely not. If you want a second host, you come to me asking (optionally with suggestions).

[re: the orchestrator's question whether an agent may open a free account on a second host for Fledge's release files.]

*Governs:* an agent never opens an account, free or paid, on any service; when one is wanted, an agent asks the maintainer, with suggestions. *Applied in:* AGENTS.md, Questions.

> One third of the reason Fledge exists is to support Lota, which is a faithful port of LÖVE2D to Ruby. Drag-to-fuse is a huge part of why LÖVE2D is successful; CLIs can be scary to newbies.

[re: the orchestrator's answer to Lota's session that Fledge has no single-file mode, no plan for one, and that Lota should assume folder-style output.]

*Governs:* single-file output and a drag-and-drop way to make an app, as LÖVE's fused games have, are in scope for Fledge, because supporting Lota is a main purpose of the project and a command line is a barrier to the people Lota is for; the earlier answer that they are excluded is withdrawn. *Applied in:* Plan 003, "Build from a built app, and the files an app opens".

> Question D. My main concern was adding a lot of code, complexity, and surface area for bugs re: cross-compiling. Anything that doesn't do those is fine by me.

[re: question D in `questions.md`, whether a repack may make one system's app on another system when it compiles nothing.]

*Governs:* making an app for another system from an already built app is allowed when it adds little code and complexity and little room for bugs, and above all when it needs no cross-compiling; the earlier rule that each system's app is built on that system (decisions, 2026-10-28) was about code that writes formats and compiles, and is not extended to a step that only copies. *Applied in:* ADR 032.

> I've decided to pay Apple, Microsoft, Google, whoever I need.

[re: the maintainer's wish to publish Dot Popper on the Play Store, App Store, Mac App Store, Windows Store, and brew, after the rulings of 2026-10-28 and 2026-11-02 that no money is spent now.]

*Governs:* the maintainer will spend money on the accounts and certificates the stores need (Apple, Microsoft, Google, a certificate authority, and others), which ends the earlier rulings that none is spent; the maintainer opens and pays for each account, since an agent never opens one, even a free one; agents plan and prepare the work that needs them (signing, notarization, store submissions) and say what each costs. *Applied in:* `doc/contributors/handoff.md`, Plan 003's store and signing stories.


## 2026-11-07

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> setdef now licenses Fledge under the MIT license.

[re: the orchestrator's account of what the AGPL cost Fledge's app developers and what it protected, after the maintainer asked for reasons not to go MIT. setdef is the registered d/b/a of the maintainer's single-member Missouri LLC, Kerrick Design, LLC.]

*Governs:* Fledge's own code is MIT, held by setdef; there is no commercial license for Fledge. It replaces decision 1 and the entries of 2026-11-06 (the additional permission, the icon, and "Option A"), which no longer govern anything. Released tags through `v0.7.0` keep the license they were released under. *Applied in:* every file's SPDX header, `LICENSE`, the gemspec, each app's `notices/NOTICES.txt`, the README, AGENTS.md, Licensing, and the ADRs that described the AGPL.

> In fact, I specifically said that ratatui_ruby-devtools is in the middle of being extracted and after that work is done by those agents we'll need to further extract the non-RatatuiRuby-ecosystem parts of it to reuse for Fledge, lota, etc.

> Only if I explicitly instruct it.

[re: an agent starting to copy RatatuiRuby's release tooling into Fledge, which the maintainer had never asked for; the second line answers whether Fledge's agents should ever do that second extraction.]

*Governs:* Fledge's release tooling (`rake bump:*`, the release task's tags, `stable`) waits until RatatuiRuby's agents finish extracting `ratatui_ruby-devtools` and its non-RatatuiRuby parts are extracted again for Fledge, Lota, and the rest; nothing is ported or copied before then, and Fledge's agents do that second extraction only when the maintainer explicitly instructs it. *Applied in:* Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0"; `doc/contributors/design/releases.md`, "From 1.0: release branches and a human publishing".

## 2026-11-08

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> I want this 1.0.0-ready pending only my manual testing (or the testing I need to prompt you to do) that is blocked on my developer accounts.

[re: the orchestrator's offer to fix the stale statements in the handoff and to write the checklist for the one `gem push`, made while the repository's readiness for 1.0.0 was being weighed.]

*Governs:* agents finish everything for 1.0.0 that the maintainer's developer accounts do not block; what those accounts block is tested by the maintainer, or by an agent he prompts to run the test. It names no test and no account, and it does not say which tests must pass before 1.0.0 is tagged. *Applied in:* `doc/contributors/handoff.md`; `doc/contributors/releasing-1.0.md`; `doc/contributors/questions.md`, question C; Plan 003.

> Yes, cut v0.X.Y releases as appropriate as we go along; my ideal is that v0.A.B (where A.B is the highest 0.X.Y release ever made) has the same features/fixes/etc. as v1.0.0 will when it gets cut.

[re: whether agents should keep cutting 0.x releases as work accumulates, given the 2026-11-08 goal of a repository that is 1.0.0-ready pending only the tests the maintainer's accounts block.]

*Governs:* agents release 0.x versions as work accumulates, so that the newest 0.x release carries what 1.0.0 will; the 1.0.0 release then adds only what the maintainer's own testing and decision add. *Applied in:* AGENTS.md, Releasing; `doc/contributors/handoff.md`.

> Keep a list of account-block tests current and clear for me to work through myself; I may decide at some point which ones I want to keep blocking 1.0.0 and which ones I don't.

[re: question C in `questions.md`, which account-blocked tests must pass before 1.0.0 is tagged, and how the maintainer is to find and run them.]

*Governs:* agents keep a list of the tests that wait on the maintainer's developer accounts, current and clear enough for the maintainer to work through alone; which of them block 1.0.0 is the maintainer's choice, made later, and until then none is named a requirement. *Applied in:* `doc/contributors/account-tests.md`; AGENTS.md, Releasing; question C in `questions.md`.

## 2026-11-09

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> If the Fledge agent and Lota agent agree, I'd rather see Fledge and Lota ship 4.1-preview now, drop 4.0 now, and not ship Fledge 1.0.0 or Lota 1.0.0 until 4.1 releases.

[re: the Lota agent's proposal that Lota and Fledge require Ruby 4.1, previews included, after Fledge's Ruby 4.1 spike (`doc/contributors/research/2026-11-09-ruby-4.1-spike.md`), and the maintainer's word before it that he would agree only if both agents did. Both agreed: Fledge's orchestrating agent on the grounds that a 1.0 on Ruby 4.0 would oblige Fledge to keep 4.0's runtimes through all of 1.x (ADR 029), on condition that the spike's open problems are fixed or explained before the first release on 4.1; the Lota agent on condition that Lota's own move lands together with that release. Fledge's orchestrating agent had also proposed a last release on Ruby 4.0.9 first, which these words leave out.]

*Governs:* Fledge's releases carry Ruby 4.1 preview runtimes in place of Ruby 4.0's, from the first release whose CI passes on every job with them; Ruby 4.0 is dropped now, but for the one release the next quotation allows; Fledge 1.0.0 is not released before Ruby 4.1.0 is, and so waits on Ruby 4.1.0 as well as on the maintainer's account-blocked testing. *Applied in:* Plan 003; ADR 056; Plan 003, "1.0"; the handoff.

> I am okay with a last-release on Ruby 4.0.9 first, as long as it doesn't meaningfully delay "now". Call it "now-ish" :)

[re: the release on Ruby 4.0.9 that the quotation above left out, which the orchestrating agent noted when it recorded that one.]

*Governs:* one last Fledge release on Ruby 4.0.9 is made before the first on Ruby 4.1, as long as it does not meaningfully delay the move to 4.1; "now" in the quotation above means as soon as that release and the 4.1 work allow. *Applied in:* release 0.11.0; Plan 003; ADR 056; Plan 003, "1.0".

## 2026-11-12

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> Very valuable, let's do it if we can.

[re: the orchestrating agent's account, after the maintainer's public poll listed `.msix` among what Fledge ships to Windows, that the Microsoft Store takes an MSIX package and Microsoft signs it during certification, so a developer who ships through the Store needs no code-signing certificate of their own, where an EXE or MSI installer submitted to the Store must be signed with the developer's own certificate.]

*Governs:* Fledge builds an MSIX package for a Windows app, if it can, so that a developer can ship through the Microsoft Store without a code-signing certificate of their own. *Applied in:* the work to add it.

> Right, Tauri 2 does phones so it must be possible. If that's the case, we should do it.

[re: the orchestrating agent's account that `fledge build` refuses a gem whose extension is written in Rust (rb-sys) for iOS and Android, because nobody has made it work there yet (ADR 022: "rb-sys was not tried"), not because it cannot work.]

*Governs:* gems whose extensions are written in Rust build for iOS and Android, as they do for the desktops. *Applied in:* the work to add it.

> Python and other languages that have Fledge-like tools must solve this somehow; so can we.

[re: the orchestrating agent's account that on a phone `fledge build` compiles a gem's extension only through its `extconf.rb`, so a gem whose gemspec names a Rakefile, CMake, or `configure` directly is refused (ADR 022).]

*Governs:* gems whose extensions build without an `extconf.rb` build for iOS and Android too, as the prior art of other languages' tools does it. *Applied in:* the work to add it.

> Why can't we have it on both? And why does Fledge leave Ruby's `fiddle` out?

[re: the orchestrating agent's recommendation to support gems that build a library for Ruby's ffi to load on Android only, and to keep refusing them on iOS, as Fledge leaves Ruby's fiddle out of iOS runtimes for App Review; the agent then found that reason was one sentence borrowed from xord/cruby, never checked, and proposed to check it against its sources and, if it fails, to support ffi libraries on both phones and restore fiddle on iOS.]

> Yes.

[re: the agent's question whether to start that work.]

*Governs:* gems whose libraries Ruby's ffi loads work on iOS and Android, and fiddle is in the iOS runtime, unless checked sources show App Review or iOS forbids them; the reason to leave either out must be cited, not assumed. *Applied in:* the work to add them.

> TRULY justified? Every difference, every lack of parity, is a knife in Fledge's back that could kill the project before it launches.

[re: the orchestrating agent's statement that every platform has 7 to 16 justified differences from `ruby main.rb` in the parity check, after two accepted justifications that day (Android's `$0 =` and `fiddle` on iOS) proved to be closable.]

*Governs:* a difference from `ruby main.rb` is accepted only when it is inherent to where the app ships or a platform truly forbids what Ruby does, shown from primary sources; one that could be closed is a bug to fix. *Applied in:* the audits of every justification and exclusion.

> experiment branches? landing commits? Merge conflicts?
>
> What happened to trunk-based development?

> I don't know why AGENTS.md says that. Read the trunk-based development skill; that's how we should work.

[re: the orchestrating agent's sub-agents each working on a branch for hours, landed later by the orchestrator, with conflicts between them; and the agent's question whether sub-agents should push `trunk` themselves, since AGENTS.md said a parallel sub-agent does not.]

*Governs:* every agent works trunk-based as trunkbaseddevelopment.com describes: small green commits pushed straight to `trunk` within minutes of being proven, no long-lived or sideways branches, no push to find out whether CI passes, and a red `trunk` reverted at once. *Applied in:* AGENTS.md, Working as an agent.
