<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Maintainer's Decisions

This file records what the maintainer has said, word for word, and nothing else. It is the source of truth for "what the maintainer decided." Everything else in this repository (the ADRs, the plans, the help header, the error messages, the layouts, this file's notes) was written by agents, and agents may change it, as long as it stays true to what is quoted here (AGENTS.md, Provenance).

Each quotation is followed by a note, written by an agent, of what it governs and where it is applied. When he quoted a sentence with `>`, that sentence is part of his words: it is kept inside the quotation, exactly as he typed it, above his answer. A "[re:" line says only what that does not, and keeps an agent's account apart from his words. When a quotation and a note disagree, the quotation wins. When a quotation seems to conflict with another, or is ambiguous, ask in `questions.md`; never guess.

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

*Governs:* the maintainer asked that agents follow the standards rather than ask (see decision 16). *Applied in:* `doc/contributors/design/public-interface.md`, "The command's conventions" (`-h`, `-?`, `--help`, `-v`, `--version`; exit status 2 for usage errors).

> 5. You invented the help header, so that's a problem you created. My instinct is to use the app's primary class/module's name, like MyCoolApp. [re: NAME in dist/NAME-PLATFORM — depends on #2, still open]

*Governs:* where NAME comes from, once decision 2 is settled. *Applied in:* `questions.md`, entry B. NAME stays the app folder's name until then.

> 6. Before the release of 1.0, you may push to trunk and you may create and push tags and you may create github releases, but you may not release to rubygems.

*Governs:* what agents may publish before 1.0. *Applied in:* AGENTS.md, Committing and Releasing; `.github/workflows/release.yml`.

> 7. 2.39 is fine, and even newer may be fine if there becomes good reason to raise the floor.

*Governs:* the oldest glibc a Linux app runs on. *Applied in:* ADR 100; `doc/contributors/design/releases.md`, "Platform floors".

> 8. Because of what I said re: #1, we must be VERY careful to be able to let app devs _not_ be copyleft-laden when they pay for a commercial license.

*Governs:* the license of everything Fledge itself copies into an app, its runtime: no third-party component may leave an app's developer with copyleft obligations beyond notices. It stands on its own since 2026-11-07, when Fledge itself became MIT ("#1" and the commercial license it names are gone). It does not reach the app's own gems, which the 2026-10-28 reply leaves to the app's developer. *Applied in:* AGENTS.md, Licensing; Plan 002, "Copyleft-free runtimes" and "Tell app developers what they owe, from CI."

> 9. When using fledge, your ruby source code should be able to be identical to how it was without Fledge, so the things you had to `require` before you can still need the app dev to `require`, but the things you didn't have to `require` before the app dev still shouldn't have to require.

*Governs:* what a runtime ships and what the launcher does to Ruby's state. *Applied in:* ADR 081; `doc/contributors/design/runtimes.md`, "What a runtime keeps"; the parity check (`tasks/parity.rb`, run in CI on every platform); `RuntimeBuilder` keeping every default and bundled gem.

> 10. All the ruby globals should be non-surprising to app devs, for the same motivation as #9.

*Governs:* `$0`, `$LOAD_PATH`, `$LOADED_FEATURES`, and every other global an app sees. *Applied in:* ADR 081; the launcher (no `-I`, no `--yjit`); the parity check.

> 11. I don't understand what I'd be deciding here. [re: restoring the person's own RUBY*/GEM*/BUNDLE* env for child processes — orchestrator is explaining; still open]

*Governs:* nothing yet. *Applied in:* `questions.md`, entry C, which tracks the follow-up. The launcher now restores the person's environment after Ruby boots, as the orchestrating agent directed (`doc/contributors/design/launcher.md`, "Hiding and restoring the person's Ruby settings").

> 12. Many CI platforms only run on musl for Linux, so I'd like to support it eventually, but it's not a blocker to continuing to iterate. It may be a blocker to 1.0 though.

*Governs:* musl Linux targets. *Applied in:* Plan 002, "musl Linux."

> 13. Again, you invented the help header. Recall the difference between what _I've said_ vs. what's on disk. You need _me_ to second-guess _me_, but you don't need _me_ to second-guess _yourself_.

*Governs:* the `fledge build` surface is the agents' to decide. *Applied in:* AGENTS.md, Questions; `doc/contributors/design/public-interface.md`, "The command's conventions".

> 14. You wrote the ADRs. Recall the difference between what _I've said_ vs. what's on disk. me/me vs. me/yourself

*Governs:* ADR content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions; `doc/contributors/design/releases.md`, "The pins" (how a version pins its runtimes).

> 15. You wrote the plans. Recall the difference between what _I've said_ vs. what's on disk. me/me vs. me/yourself

*Governs:* plan content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions; Plan 001 (what hello prints).

> 16. Why is this something I should decide? Isn't this something where there's prior art or an industry standard we can/should follow?

*Governs:* behavior with prior art or a standard is the agents' to decide, citing it. *Applied in:* AGENTS.md, Questions; `doc/contributors/design/public-interface.md`, "The command's conventions"; `doc/contributors/design/launcher.md`, "Messages and exit statuses" (launcher errors follow `ruby:` messages and sysexits.h).

> 17. Ideally, fledge developers should have the option to make it so Windows/macOS don't block the use of the app. But not every app dev will have the done the required ceremony with Microsoft and/or Apple.

*Governs:* code signing and notarization: an option for developers who have the credentials, with unsigned builds still working. *Applied in:* Plan 002, "Signing and notarization."

> 18. Would this affect what shows up in the taskbar? task manager? start menu? desktop icons? app window top-left corner and/or title bar? If so, app devs need to be able to control it.

*Governs:* an app's icon, name, and version information on every OS are the developer's to control. *Applied in:* Plan 002, "App identity."

> 19. I don't understand what I'd be deciding here. [re: RubyInstaller signing key expiry — agents own this]

*Governs:* the RubyInstaller signing key is the agents' to manage. *Applied in:* ADR 100; `doc/contributors/design/runtimes.md`, "The RubyInstaller signing key"; `runtime/sources.yml`.

> 20. Tiny filesize is not a priority; "my ruby code just works" _is_ a (high) priority.

*Governs:* what runtimes prune: only what no running Ruby code can observe. *Applied in:* `doc/contributors/design/runtimes.md`, "What a runtime keeps" and "What a runtime prunes, and why nothing reads it"; `RuntimeBuilder::Pruning.prune`.

> 21. I don't understand what I'd be deciding here. [re: Windows console code pages and Ctrl-C — agents own this]

*Governs:* console code pages and Ctrl-C on Windows are the agents' to decide. *Applied in:* ADR 081 (the launcher matches `ruby.exe`, but for the ANSI code page: `doc/contributors/design/launcher.md`, "The locale"); the parity check's `chcp 437` run; Plan 002, "Ctrl-C and the console."

> 22. I'd like to support Windows on ARM (and Linux on ARM) eventually, but it's not a blocker to continuing to iterate. It may be a blocker to 1.0 though.

*Governs:* ARM targets. Linux on ARM already ships as `aarch64-linux`. *Applied in:* Plan 002, "Windows on ARM."

> 23. Would this require app devs to have a bunch of `if`s or polymorphic objects used throughout their app to handle the difference? [re: Windows ruby\ vs Unix lib/ layout — answer is no; agents own this]

*Governs:* the internal layout of a runtime is the agents' to decide, as long as app code needs no per-OS branches for it. *Applied in:* `doc/contributors/design/runtimes.md`, "Layout on Windows".

> 24. See #8 [re: GMP being LGPL]

*Governs:* GMP, like every other component of a runtime, falls under decision 8. *Applied in:* Plan 002, "Copyleft-free runtimes."

## 2026-10-26, later

Replies to the orchestrating agent's answers in chat, quoted from the maintainer's messages. The orchestrating agent recorded them, because the maintainer, asked whether it could, said "You may" (2026-10-27). Brackets say what each reply answered.

> 2. Ok.

[re: what the options are besides a folder with a `main.rb`: the orchestrator offered (a) a folder with a `main.rb`; (b) the executable you already run, such as `exe/my_cool_app` or `bin/server`, with the project root where the Gemfile or gemspec is; (c) a configuration file naming the entry point; (d) the gemspec's `executables`. It recommended (b), with configuration only where it's needed, and NAME taken from the project (the gemspec's name or the folder's, camelized, such as `MyCoolApp`), which configuration can override.]

*Governs:* an app's layout and entry point, and, with decision 5, where NAME comes from. *Applied in:* Plan 002, "Ship the executable you already run."

> 4. Ok.

[re: the CLI conventions: `-h`, `-?`, and `--help`, and `-v` and `--version`, print to standard output and exit 0; a usage error prints a short usage to standard error and exits 2.]

*Governs:* the CLI conventions. *Applied in:* `doc/contributors/design/public-interface.md`, "The command's conventions".

> 11. I think yes?

[re: whether to restore the person's own `RUBYOPT`, `GEM_*`, `BUNDLE_*`, and the rest into `ENV` after Ruby has booted, so the app's `ENV` and its child processes look as they would without Fledge, while the app's own boot stays protected. The orchestrator recommended restoring.]

*Governs:* the environment an app and its child processes see. *Applied in:* `doc/contributors/design/launcher.md`, "Hiding and restoring the person's Ruby settings"; `runtime/launcher/unix.c` and `windows.c`; the parity check and Delivery.

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

*Governs:* Fledge takes no position on the licenses of the gems an app depends on — those are the app developer's choice and responsibility; decision 8 and the LGPL replies govern only what Fledge itself puts into apps (its runtime). *Applied in:* `doc/contributors/design/gems.md`, "Checks that are not about licenses"; AGENTS.md, Licensing; `Fledge::AppGems`, which no longer judges a gem's license or what its compiled files hold, and `Fledge::Linkage`, which checks only that they load; `fledge.yml`, which no longer has `licenses` or `compiled`; the removal of `lib/fledge/compiled_code.yml`, `Fledge::RustCrates`, and `notices/GEMS.txt`; `doc/licensing.md`, "Your app's own gems"; the README; `exe/fledge`'s help; Plan 002; `test/fixtures/native_app`, which ships spreadsheet (GPL-3.0), and `test/fixtures/nokogiri_app`, which ships for Windows with GNU libiconv linked in.

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

*Governs:* agents spend no money on Android's arm64-v8a proof: no device cloud, paid runner, or machine; the story waits for a free way to run it. *Applied in:* Plan 003, "Android on arm64"; ADR 099 and ADR 012.

> We can't spend money on this right now.

[re: `questions.md` entries A and B, asked in the same session as the Android answer above: an Apple Developer account for a real iPhone and iPad, App Review, Developer ID, and notarization, and a Windows code signing certificate or Azure Trusted Signing account. The orchestrator had said the Apple account was probably due, and the Windows half was not. The maintainer's words follow the question of whether it was the last responsible moment for each.]

*Governs:* agents open and pay for no account, certificate, device, or service, including Apple's, Microsoft's, and a certificate authority's, until the maintainer says otherwise; the stories that need one wait. *Applied in:* Plan 003, "iOS on a real device, and App Review" and "Notarization and real trust chains"; ADR 012 and `doc/contributors/design/signing.md`, "What CI proves, and the stand-ins", which already list what is unproven; `questions.md`, entry D.

## 2026-11-02

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> 1. No 1.0 until at least some of these things are proven. But we can go from A.B.C.pre.D to 0.1.0 sem-ver style.
> 2. We really shouldn't have external dependencies on those repos; they are expected to depend upon us, not the other way around.
> 3. Go for .deb

[re: the orchestrator's briefing of what it needed: (1) `questions.md` entry D, whether 1.0 may ship with iOS on a real device and App Review, real signing trust chains, and Android arm64 unproven; (2) two unsent drafts, one asking Rooibos to add CI jobs that build its app with a tagged Fledge and one telling Tokra what Fledge now has, the first of which completed Plan 003's wrapper story only if Rooibos's own CI ran it; (3) optional work, of which the `.deb` installer was the cheapest. The numbering is the maintainer's, answering that briefing.]

*Governs:* 1.0 waits until at least some of the unproven things are proven; releases may move from the `0.0.1.pre.N` form to ordinary 0.MINOR.PATCH versions, beginning with 0.1.0; Fledge depends on no wrapper's repository, wrappers depend on Fledge; a `.deb` installer is built. *Applied in:* Plan 003; `questions.md` (entry D removed); the drafts; the next release.

> iPadOS, iOS, and Android are our priorities for 0.2.0.

[re: the orchestrating agent had written: "do you want the plan changed so native gems on phones come before 1.0?"]

*Governs:* the work for release 0.2.0 is phones: iPadOS, iOS, and Android, ahead of the stories that wait on money. *Applied in:* Plan 003.

## 2026-11-02, later

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> "Never publish to RubyGems.org" was an instruction to agents (for AGENTS.md) not a position the project takes; even when the library is on RubyGems.org I'll continue to make that a human-only activity.

[re: a draft line saying Fledge is "never" installed from RubyGems.org, which followed AGENTS.md's "Never publish to RubyGems.org" as if that rule were a position of the project.]

*Governs:* publishing to RubyGems.org is a human-only activity, whether or not Fledge is on RubyGems.org; the earlier "Never publish to RubyGems.org" and decision 6's "you may not release to rubygems" bind agents and say nothing about the project, so documents for developers do not say Fledge is never published there. *Applied in:* AGENTS.md, Releasing; Plan 003, "1.0"; `doc/contributors/design/releases.md`, "Where releases are".

## 2026-11-02, later again

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> I use three words for how code and prose comes to exist. Code I wrote, I typed by hand, with nothing generated. Code I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I take responsibility for every diff. Code I requested, an agent built with little or no review from me, in the style of a "dark factory."

[re: after asking "Do you have the exact quote?", he sent these words marked with `>`, and then wrote: "You can drop "or prose" from it." The three "or prose" are left out above.]

*Governs:* what *written*, *wrought*, and *requested* mean wherever Fledge uses them: the `Provenance:` trailer, AGENTS.md, and the README's disclosure. *Applied in:* AGENTS.md, Provenance; the README.

> I want to get to "I can playtest [a game written in Ruby using Lota] on [an M1 iPad Pro running iPadOS 27] and [a OnePlus Nord N30 5G running Android 13]" as the litmus test for "phones and tablets" (0.2.0).

[re: the orchestrator's report that native gems with C and C++ extensions now run on phones in CI, and its answer that a Lota game could not yet be deployed to a tablet. The maintainer's words named the game and the devices, and then made them specific; the brackets stand for what the maintainer named.]

*Governs:* release 0.2.0 means a Ruby game on Lota can be playtested on an iPad and on an Android phone, built through Fledge. *Applied in:* Plan 003, "A game plays on a tablet and a phone".

> Remember: this entire rule is because _Fledge should never surprise an app dev with how it behaves or causes Ruby or its globals, built-ins, and standard library to behave compared to not using Fledge_.

[re: Design precedence 2, in the discussion of whether a restart through `RbConfig.ruby` in a built app differs from `ruby main.rb`.]

*Governs:* the purpose of Design precedence 2 and of the parity check: a difference between a Fledge app and the same program run without Fledge is a bug unless it is justified and documented. *Applied in:* AGENTS.md, Design precedence 2; `doc/contributors/design/launcher.md`, "bin/ruby and restarts".

## 2026-11-03

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> Once we hit 1.0.0, we will be releasing via RubyGems (human only), not relying on GitHub Releases and git tags.

[re: his own question, "Are major version bumps after 1.0.0 my decision or yours?", and the orchestrating agent's comparison of ways to release them, which ended: "Tell me which option you want."]

*Governs:* from 1.0.0, Fledge is also released on RubyGems.org, by a human, so a release can be found there as well as by its git tag and GitHub Release; before 1.0.0 it is found only by its tag and GitHub Release, and nothing is pushed to RubyGems.org (the maintainer's explanation of 2026-11-04, below). Agents prepare a release and never publish it. *Applied in:* Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0"; AGENTS.md, Releasing.

> I can buy that for now, but will easily be swayed by the first app dev who gets upset by the deviation. And we shouldn't be cagey about it or hide it.

[re: the orchestrating agent had written, of the launcher's turning a bare C locale into a UTF-8 one: "So coercing is Fledge improving on plain Ruby, not matching it. I think that is the right trade under Design precedence 1, for this one case."]

*Governs:* the locale coercion stays until the first app developer reports it as a surprise, then it is reversed; and any deviation from plain Ruby is documented where app developers read, plainly. *Applied in:* the README; `doc/contributors/design/launcher.md`, "The locale"; `Parity::JUSTIFIED`.

> A minor release can make additional rubies available, but can only change the defaults' patch versions--unless we abandon the concept of default entirely, and require app devs to specify a version (maybe better?); then it's limited to e.g. generated config files, which can change in a minor version because they don't get re-generated on upgrade.
>
> Ruby doesn't follow SemVer, so 4.1 is expected to have breaking changes from 4.0.
>
> I require a major version bump to drop support for a ruby, or to drop support for an OS "version" (the thing that differentiates MacOS 26 from MacOS 27, not patches etc.).

[re: the orchestrating agent had written: "A: may a 1.x release change the Ruby inside apps, or raise the minimum operating system, or must it wait for a major?"]

*Governs:* a minor release may add Rubies and may change only a default Ruby's patch version; the maintainer is open to having no default Ruby, with the app developer naming the version (the orchestrator is to weigh it); generated config files may change in a minor release because an upgrade does not regenerate them; a new Ruby minor is expected to break (Ruby does not follow SemVer); dropping a Ruby, or an operating system version (macOS 26 against 27, not a patch), requires a major version. *Applied in:* `doc/contributors/design/releases.md`, "Versions" and "Ruby minors and runtimes"; `doc/contributors/design/public-interface.md`.

> We'll be reusing the git/ruby version stuff from RatatuiRuby and Rooibos. How tags work (and release branches, backports, etc.) differ before and after 1.0.0.

[re: the orchestrating agent had written: "B: after 1.0, does a release still get a git tag?"]

*Governs:* Fledge's versioning, tagging, release branches, and backports reuse what RatatuiRuby and Rooibos do, and work differently before 1.0.0 and after it; the tooling itself waits on its extraction (2026-11-07, below). *Applied in:* `doc/contributors/design/releases.md`, "Versions" and "From 1.0: release branches and a human publishing"; Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0".

> winget, Chocolatey, Scoop, brew, apt-get, pacman, dnf, etc. are all very relevant for Ruby console apps.

[re: the orchestrating agent had written: "Whether channels beyond the stores are in scope for Fledge at all is yours to say."]

*Governs:* the package managers (winget, Chocolatey, Scoop, Homebrew, apt-get, pacman, dnf, and others) are in scope for Fledge's console apps; a decision that Fledge does not target them is not made, and none is to be recorded. *Applied in:* `doc/contributors/research/2026-11-04-app-stores.md` (which the package managers extend); Plan 003.

## 2026-11-04

The maintainer wrote this after the orchestrating agent had misread the sentence of 2026-11-03 above ("not relying on GitHub Releases and git tags"). It is quoted in part: the dictionary definitions of "rely", "dependent", "require", and "necessity" that followed it are left out.

> > Once we hit 1.0.0, we will be releasing via RubyGems (human only), not relying on GitHub Releases and git tags.
>
> Prior to 1.0.0, this gem would not release via RubyGems by using `gem push`. This is because prior to 1.0.0 I don't know if it'll succeed and I don't want to be a name squatter with a failed project.
> Both before and after 1.0.0, it is expected that, like RatatuiRuby before, all releases will be findable via git tags in the source repos, which automatically become GitHub Relaeses.
> Only before 1.0.0, that is the _only_ way they'll be findable, so releases **rely** on GitHub Releases / git tags.
> After 1.0.0, that is _one way_ they'll be findable, so releases do not **rely** on GitHub Releases / git tags, they can be found another way too.

*Governs:* nothing is pushed to RubyGems.org before 1.0.0; every release, before and after, has its git tag and the GitHub Release made from it; from 1.0.0 a release is also on RubyGems.org, and "not relying" means only that. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`, "Where releases are" and "From 1.0: release branches and a human publishing"; `doc/contributors/design/public-interface.md`, "Frozen for 1.x"; Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0".

> > "may an agent open a free account on a second host?"
>
> Absolutely not. If you want a second host, you come to me asking (optionally with suggestions).

*Governs:* an agent never opens an account, free or paid, on any service; when one is wanted, an agent asks the maintainer, with suggestions. *Applied in:* AGENTS.md, Questions.

> One third of the reason Fledge exists is to support Lota, which is a faithful port of LÖVE2D to Ruby. Drag-to-fuse is a huge part of why LÖVE2D is successful; CLIs can be scary to newbies.

[re: the orchestrating agent had written, of its answer to Lota's session: "I told them to assume folder-style output."]

*Governs:* single-file output and a drag-and-drop way to make an app, as LÖVE's fused games have, are in scope for Fledge, because supporting Lota is a main purpose of the project and a command line is a barrier to the people Lota is for; the earlier answer that they are excluded is withdrawn. *Applied in:* Plan 003, "Build from a built app, and the files an app opens".

> Question D. My main concern was adding a lot of code, complexity, and surface area for bugs re: cross-compiling. Anything that doesn't do those is fine by me.

[re: question D in `questions.md`, whether a repack may make one system's app on another system when it compiles nothing.]

*Governs:* making an app for another system from an already built app is allowed when it adds little code and complexity and little room for bugs, and above all when it needs no cross-compiling; the earlier rule that each system's app is built on that system (decisions, 2026-10-28) was about code that writes formats and compiles, and is not extended to a step that only copies. *Applied in:* `doc/contributors/design/desktop-apps.md`, "Building from a built app".

> I've decided to pay Apple, Microsoft, Google, whoever I need.

[re: the maintainer's wish to publish Dot Popper on the Play Store, App Store, Mac App Store, Windows Store, and brew, after the rulings of 2026-10-28 and 2026-11-02 that no money is spent now.]

*Governs:* the maintainer will spend money on the accounts and certificates the stores need (Apple, Microsoft, Google, a certificate authority, and others), which ends the earlier rulings that none is spent; the maintainer opens and pays for each account, since an agent never opens one, even a free one; agents plan and prepare the work that needs them (signing, notarization, store submissions) and say what each costs. *Applied in:* Plan 003's store and signing stories.


## 2026-11-07

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> setdef now licenses Fledge under the MIT license.

[re: the orchestrating agent had written: "Say "MIT" and I'll quote you in `decisions.md`, then have an agent list everything the change touches, for you to review before anything lands." setdef is the registered d/b/a of the maintainer's single-member Missouri LLC, Kerrick Design, LLC.]

*Governs:* Fledge's own code is MIT, held by setdef; there is no commercial license for Fledge. It replaces decision 1 and the entries of 2026-11-06 (the additional permission, the icon, and "Option A"), which no longer govern anything. Released tags through `v0.7.0` keep the license they were released under. *Applied in:* every file's SPDX header, `LICENSE`, the gemspec, each app's `notices/NOTICES.txt`, the README, AGENTS.md, Licensing, and the ADRs that described the AGPL.

> In fact, I specifically said that ratatui_ruby-devtools is in the middle of being extracted and after that work is done by those agents we'll need to further extract the non-RatatuiRuby-ecosystem parts of it to reuse for Fledge, lota, etc.

> Only if I explicitly instruct it.

[re: he had just written: "I never said you may port RatatuiRuby's release tooling." The second line answers the orchestrating agent's "Should Fledge's agents ever be the ones to do that second extraction, or is it always the RatatuiRuby side's?"]

*Governs:* Fledge's release tooling (`rake bump:*`, the release task's tags, `stable`) waits until RatatuiRuby's agents finish extracting `ratatui_ruby-devtools` and its non-RatatuiRuby parts are extracted again for Fledge, Lota, and the rest; nothing is ported or copied before then, and Fledge's agents do that second extraction only when the maintainer explicitly instructs it. *Applied in:* Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0"; `doc/contributors/design/releases.md`, "From 1.0: release branches and a human publishing".

## 2026-11-08

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> I want this 1.0.0-ready pending only my manual testing (or the testing I need to prompt you to do) that is blocked on my developer accounts.

[re: the orchestrating agent had written: "What would you like next: those doc fixes, the `gem push` checklist, or something else?" His message began "All of the above."]

*Governs:* agents finish everything for 1.0.0 that the maintainer's developer accounts do not block; what those accounts block is tested by the maintainer, or by an agent he prompts to run the test. It names no test and no account, and it does not say which tests must pass before 1.0.0 is tagged. *Applied in:* `doc/contributors/releasing-1.0.md`; `doc/contributors/questions.md`, question C; Plan 003.

> Yes, cut v0.X.Y releases as appropriate as we go along; my ideal is that v0.A.B (where A.B is the highest 0.X.Y release ever made) has the same features/fixes/etc. as v1.0.0 will when it gets cut.

[re: the orchestrating agent had written: "Should I cut v0.10.0 now?"]

*Governs:* agents release 0.x versions as work accumulates, so that the newest 0.x release carries what 1.0.0 will; the 1.0.0 release then adds only what the maintainer's own testing and decision add. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`, "Versions".

> Keep a list of account-block tests current and clear for me to work through myself; I may decide at some point which ones I want to keep blocking 1.0.0 and which ones I don't.

[re: the orchestrating agent had written: "Which of the account-blocked tests must pass before 1.0.0 is tagged?"]

*Governs:* agents keep a list of the tests that wait on the maintainer's developer accounts, current and clear enough for the maintainer to work through alone; which of them block 1.0.0 is the maintainer's choice, made later, and until then none is named a requirement. *Applied in:* `doc/contributors/account-tests.md`; AGENTS.md, Releasing; question C in `questions.md`.

## 2026-11-09

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> If the Fledge agent and Lota agent agree, I'd rather see Fledge and Lota ship 4.1-preview now, drop 4.0 now, and not ship Fledge 1.0.0 or Lota 1.0.0 until 4.1 releases.

[re: the orchestrating agent had written: "If that's your yes, say it in your own words; that's what goes into `decisions.md`." The Lota agent had proposed that Lota and Fledge require Ruby 4.1, previews included, after Fledge's Ruby 4.1 spike (`doc/contributors/research/2026-11-09-ruby-4.1-spike.md`).]

*Governs:* Fledge's releases carry Ruby 4.1 preview runtimes in place of Ruby 4.0's, from the first release whose CI passes on every job with them; Ruby 4.0 is dropped now, but for the one release the next quotation allows; Fledge 1.0.0 is not released before Ruby 4.1.0 is, and so waits on Ruby 4.1.0 as well as on the maintainer's account-blocked testing. *Applied in:* Plan 003; `doc/contributors/design/releases.md`, "Ruby minors and runtimes"; Plan 003, "1.0".

> I am okay with a last-release on Ruby 4.0.9 first, as long as it doesn't meaningfully delay "now". Call it "now-ish" :)

[re: the orchestrating agent had written: "Fledge agrees with that. It differs from my conditions in one place: no last release on Ruby 4.0.9 first."]

*Governs:* one last Fledge release on Ruby 4.0.9 is made before the first on Ruby 4.1, as long as it does not meaningfully delay the move to 4.1; "now" in the quotation above means as soon as that release and the 4.1 work allow. *Applied in:* release 0.11.0; Plan 003; `doc/contributors/design/releases.md`, "Ruby minors and runtimes"; Plan 003, "1.0".

## 2026-11-12

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> > An MSIX submission: you upload it to Partner Center, and Microsoft signs it during certification. For the Store, you need no code-signing certificate of your own. That's the strongest argument for MSIX.
>
> Very valuable, let's do it if we can.

*Governs:* Fledge builds an MSIX package for a Windows app, if it can, so that a developer can ship through the Microsoft Store without a code-signing certificate of their own. *Applied in:* the work to add it.

> > So it's refused because nobody has made it work yet, not because it can't work.
>
> Right, Tauri 2 does phones so it must be possible. If that's the case, we should do it.

[re: how gems with extensions build for the phones now is `doc/contributors/design/phone-projects.md`, "Gems with extensions".]

*Governs:* gems whose extensions are written in Rust build for iOS and Android, as they do for the desktops. *Applied in:* the work to add it.

> > Extensions built without an extconf.rb (a gemspec that names a Rakefile, CMake or configure directly) give Fledge no hook to aim the build at the phone, or to get a static archive out.
>
> Python and other languages that have Fledge-like tools must solve this somehow; so can we.

[re: what is refused on a phone now is `doc/contributors/design/phone-projects.md`, "Refusals".]

*Governs:* gems whose extensions build without an `extconf.rb` build for iOS and Android too, as the prior art of other languages' tools does it. *Applied in:* the work to add it.

> > ffi gems on phones.
>
> Why can't we have it on both? And why does Fledge leave Ruby's `fiddle` out?

> Yes.

[re: the orchestrating agent had written: "Shall I start it?"]

*Governs:* gems whose libraries Ruby's ffi loads work on iOS and Android, and fiddle is in the iOS runtime, unless checked sources show App Review or iOS forbids them; the reason to leave either out must be cited, not assumed. *Applied in:* the work to add them.

> > Every platform has justified differences
>
> TRULY justified? Every difference, every lack of parity, is a knife in Fledge's back that could kill the project before it launches.

[re: the orchestrating agent had said every platform has 7 to 16 justified differences from `ruby main.rb` in the parity check, after two accepted justifications that day (Android's `$0 =` and `fiddle` on iOS) proved to be closable.]

*Governs:* a difference from `ruby main.rb` is accepted only when it is inherent to where the app ships or a platform truly forbids what Ruby does, shown from primary sources; one that could be closed is a bug to fix. *Applied in:* the audits of every justification and exclusion.

> experiment branches? landing commits? Merge conflicts?
>
> What happened to trunk-based development?

[re: the orchestrating agent's sub-agents were each working on a branch for hours, landed later by the orchestrator, with conflicts between them.]

> I don't know why AGENTS.md says that. Read the trunk-based development skill; that's how we should work.

[re: he chose this answer to the orchestrating agent's question: "To make the work trunk-based again, sub-agents have to integrate within minutes. AGENTS.md says a parallel sub-agent never pushes trunk, so today every change waits for me to land it, and branches pile up. How do you want it?"]

*Governs:* every agent works trunk-based as trunkbaseddevelopment.com describes: small green commits pushed straight to `trunk` within minutes of being proven, no long-lived or sideways branches, no push to find out whether CI passes, and a red `trunk` reverted at once. *Applied in:* AGENTS.md, Working as an agent.

## 2026-11-19

The orchestrating agent received these words first-hand from the maintainer.

> Does WIP get us to 0.X.0, where X is the Release Candidate for 1.0.0?

[re: the work then in flight was all on CI's reliability. The orchestrating agent answered that it did not, and wrote: "The candidate moves with your testing."]

> My goal by 7:59am is to get Fledge to that release candidate release. My testing happens _on_ the release candidate, which, if it all passes, will be simply made into 1.0.0.

*Governs:* one 0.x release is the release candidate for 1.0.0, and has everything 1.0.0 will; the maintainer's testing is done on that release; and if all of it passes, 1.0.0 is made from it, with no feature or fix added between the two. The hour is that night's goal and governs nothing after it. *Applied in:* `doc/contributors/design/releases.md`, "Versions"; `questions.md`, question C.

## 2026-11-21

The orchestrating agent received these words first-hand from the maintainer.

> Wait did you say windows TEN? Lol https://support.microsoft.com/en-us/windows/deployment/updates-lifecycle/windows-10-support-has-ended-on-october-14-2025

[re: the orchestrating agent had written: "Windows 10: the README claims Windows 10, and no built app has ever run on a real Windows 10 machine." The maintainer had said he ran a game on it; the game's own records showed that run, of 2026-11-05, to have been on Windows 11.]

*Governs:* Fledge does not name Windows 10 as a system its apps run on: Microsoft's support for it ended on 2025-10-14, before Fledge's first release. The oldest Windows Fledge names is Windows 11. *Applied in:* `README.md`; `README.rdoc`; `doc/contributors/design/releases.md`, "Platform floors"; `doc/contributors/account-tests.md`.

> > Known defects
>
> How can you possibly think we can ship 1.0.0 with **known** bugs?

*Governs:* the candidate for 1.0.0 is a release with no bug the project knows of. A known defect is fixed, or shown not to be one, before a release is called the candidate; it is not listed beside it. *Applied in:* `doc/contributors/design/releases.md`, "Versions".

> we've gotta figure out how to start testing not just Windows on much more recent rubies.

[re: Fledge's runtimes then carrying Ruby 4.1.0-preview1, of 2026-10-11, on every system but Windows, whose Ruby was a build of Ruby's main branch of 2026-11-10, while Fledge 1.0.0 waits for Ruby 4.1.0. These words end a longer sentence; its beginning is left out.]

> And hey, Fledge needs to support Lota and Tokra in _their_ goals to test with Fledge's releases and shipping sample apps on more recent rubies too, right?

[re: the orchestrating agent had written: "I passed your question to the agent working on this, so its design says where `ruby-dev` fits." It answered yes to this, and took the question as direction.]

*Governs:* Fledge is tested against a recent Ruby on every platform, not only on Windows; and before 1.0 a release may carry a recent snapshot of Ruby's main branch on every platform, built by Fledge where no project publishes one that can move, so that the frameworks built on Fledge can test with its releases and ship their sample apps on it. *Applied in:* `.github/workflows/ruby-master.yml`; `doc/contributors/design/runtimes.md`, "Testing against Ruby's master" and "Fledge's own Ruby builds".

> > ## G. May Fledge copy Microsoft's Visual C++ runtime into a Windows app? (open, no deadline)
>
> An app developer who has the rights to do a thing should _be able_ to do it and distribute their app with Fledge.

[re: between the quoted heading and these words he wrote: "I am not a lawyer or a MS-ecosystem dev. I have no idea what any of this means from any angle. But I think once I saw something related in an installer I ran on my PC maybe?"]

*Governs:* where distributing a file with an app needs a right only the app's developer can hold, Fledge gives the developer a way to do it, and does not refuse the app for want of a right it cannot check; the right, and the duty to hold it, stay the developer's, as a gem's license does (2026-10-28). *Applied in:* the work to let a Windows app carry the Visual C++ runtime.

> > distributing Microsoft's files
>
> Neither should setdef, right?

*Governs:* nothing setdef publishes carries Microsoft's Visual C++ runtime: not the gem, not a runtime, not a release's files, not a fixture in the repository, and not an app that Fledge's CI builds and uploads. The files go only from a developer's own computer into that developer's own app. *Applied in:* `doc/contributors/design/gems.md`, "The Visual C++ runtime"; the tests' stand-in DLLs.

> This is not the kind of thing that belongs in-repo.

[re: his message was the command `rm doc/contributors/handoff.md`, then a comment of these words. `doc/contributors/handoff.md` was the page where agents kept where the project stands, the bugs it knows of, and what to do next.]

*Governs:* the repository holds no running account of the project's state for the next session; that is kept outside it. What a contributor needs to check or release Fledge stays in the contributor documents. *Applied in:* the removal of `doc/contributors/handoff.md`, whose checks and release steps are in CONTRIBUTING.md, "After a push" and "When CI fails", and `doc/contributors/design/releases.md`, "How a release is made"; AGENTS.md, Project.

> `examples/` is for examples, not tests/fixtures. You can have integration tests too, but examples should at least be... kinda useful/real a bit. Like, they can be silly simple (e.g. LibUI could just be a single screen toy app that does one useful thing, maybe with a second settings screen just to show off the various form etc. UI element types & a menu bar to open settings), but _realistic_. If an app just opens & exits, that's a test or a fixture not an `examples/`.

[re: an example app on the LibUI gem that an agent had written to open a window, write a report of itself, and quit, so that a check could run it.]

*Governs:* an app under `examples/` is a small realistic app that does something useful, however simple; an app that exists to be checked, and only starts and exits, is a fixture under `test/`, with the integration tests. *Applied in:* the LibUI example and its fixture; the review of the other examples.

## 2026-11-22

The orchestrating agent received these words first-hand from the maintainer.

> question G is a confusing slop storm. It seems like it was written by a lower quality model that doesn't understand the difference between Fledge's bug and somebody else's bug.

[re: the orchestrating agent had written, as item 5 of its numbered questions, of question G: "It asks whether a limit the platform itself imposes counts as a bug the candidate may not have." His message answered its numbered items.]

*Governs:* the question is withdrawn. The agents read his words so: a fault in a platform, a gem, or another project is that project's bug, not one of Fledge's known bugs, and it does not keep a release from being the candidate. Fledge's part is to show it from the other project's own documentation or source, and to say it where a developer reads. Anything Fledge itself could close is Fledge's bug. *Applied in:* `doc/contributors/design/releases.md`, "Versions"; the removal of question G from `questions.md`.

> > Security updates become Fledge's duty to notice.
>
> This scares me. Unless it can be fully automated e.g. with GitHub Actions.

> > Security updates: most of that duty exists already, and the noticing can be automated.
>
> I don't think we can call any version without that a release candidate, then.

> > automation that notices
>
> Not that notices. That takes care of all of it. I don't want to be pinged, I want Fledge to just... get a new release. (on the happy path)

*Governs:* the candidate for 1.0.0 has automation that takes care of all of it: when an input a runtime is built from has a newer release upstream, Fledge moves the pin, proves the new runtimes in CI, and releases, with no person or agent in the loop on the happy path, and the maintainer is not pinged. A person is called only when that path fails. This governs what Fledge does with a release an upstream has made. It does not make Fledge the maker of releases its upstreams have not made: a library compiled into another project's build of Ruby (jdx/ruby's, RubyInstaller's) is as new as that project's newest build, and a lag there is a stated dependency, not a failure of this rule and not a reason for Fledge to build that Ruby itself (the entry of 2026-11-22 on trusting mise, below). *Applied in:* `doc/contributors/design/releases.md`, "Versions"; the scheduled workflow that keeps the pins current.

> > One thing is yours and I've told the agent not to decide it. From 1.0, your rule is that publishing to RubyGems.org is done by a human only.
>
> My reading of this is that if a human decides to trust a deterministic process with it, that counts as a human decision. For example, trusting `gem push` instead of making raw HTTP requests. For another example... trusting GitHub Actions.

*Governs:* a deterministic process that the maintainer has decided to trust may publish Fledge to RubyGems.org, and that counts as the human's act: a GitHub Actions workflow, once he has set RubyGems.org to trust it. An agent still never publishes there itself, and never sets up that trust, which is done in his account. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`.

> > Fledge promises macOS 14.
>
> That's... really old. Older than I would've guessed. Older that Apple supports maybe even?

> I'd be okay moving the floor to 15 for now, and maybe 26 if it becomes costly to keep it at 15.

*Governs:* the oldest macOS a Fledge app runs on may be raised to 15, and to 26 if keeping 15 becomes costly. *Applied in:* `doc/contributors/design/releases.md`, "Platform floors", when the floor moves.

> > Is the glibc switch fine to land before the candidate?
>
> Yes, and so would be switching away from rv-ruby entirely if you so judge it valuable.

*Governs:* the Linux Ruby's source may change before the candidate, and whether Fledge takes any Ruby from rv-ruby at all is the agents' to judge. This replaces "2.39 is fine" (2026-10-26, decision 7) as the word on the Linux floor: a lower floor is wanted where a maintained upstream gives it. *Applied in:* ADR 100.

> > Expect no candidate in these six hours.
>
> I expect solid work towards a candidate, I am not setting a deadline. Quality!

*Governs:* there is no deadline, and quality comes first.

> > which is how other bundlers such as PyInstaller handle it.
>
> As long as setdef and/or Fledge aren't taking responsibility for any kinds of licenses here, and the App Dev is making choices so they can comply with licensing, you can do it if you think it's correct. And if you do, it should probably be in 1.0.0's release candidate 0.X.y release, right?

[re: on a Mac, `fledge build` refuses a gem whose compiled files link a library that the developer installed with a package manager such as Homebrew, since the library would be missing on the computer of a person who runs the app. The orchestrating agent had recommended that Fledge copy such libraries from the developer's Mac into the app.]

*Governs:* Fledge may carry, in a Mac app, libraries from the developer's computer that the app's gems link, when the app's developer chooses it. The choice and the licenses of what is carried are the developer's, as with the app's gems (2026-10-28); neither setdef nor Fledge takes responsibility for them. Whether to build it is the agents' to judge; if built, it is in the candidate for 1.0.0. *Applied in:* the design document for gems, when it is built.

> Whatever you can do to reduce wall clock time, reduce risk of red on trunk, reduce metered usage, hasten cycle time, increase confidence, and decrease actual-real-world-regression risk is great.

[re: of CI: the per-push check took 1 to 3 minutes and the full run about an hour, and a runtime change had passed the first and broken the second.]

> All that potential software AND legal complexity was answered by just... not caching? Silly to even have suggested caching, then.

[re: the orchestrating agent had written: "If you agree, say "no" and the next session removes K, records the decision, and builds those two items." It had recommended against publishing copies of the files Gradle downloads, and for relying on Gradle's own retries, and read his reply as no and told him so; he did not object.]

*Governs:* Fledge publishes no copies of the files Gradle downloads, and keeps no pinned sets of them; CI relies on Gradle's own retries. *Applied in:* `doc/contributors/design/phone-projects.md`, "Gradle's downloads in CI".

> > What's left in question I is a hypothetical
>
> a hypothetical is not a meaningful question

*Governs:* agents do not put a hypothetical to the maintainer; a question is about something that exists or is about to. *Applied in:* AGENTS.md, Questions.

> > Nobody checked until I stumbled on it ten minutes ago
>
> Whenever we're adding a platform, that should be the first thing we check before building our own.

[re: "That" is whether a maintained project already publishes a portable Ruby for the platform. rv-ruby publishes musl Linux builds, and Fledge builds its own.]

*Governs:* a standing rule: when a platform is added, the first check is whether a maintained project already publishes a portable Ruby for it, before Fledge builds one. *Applied in:* AGENTS.md, How to work.

> > What it costs: apps would need macOS 26 or newer.
>
> What else it buys: Intel Mac is a non-decision.

[re: jdx/ruby builds no Intel Mac Ruby, and rv-ruby's Intel build was the only one Fledge could have taken.]

*Governs:* Fledge builds no Intel Mac apps, since no maintained project publishes an Intel Mac Ruby that Fledge takes; whether to build them is no longer a question. *Applied in:* ADR 100; `doc/contributors/design/runtimes.md`, "The Mac's Ruby is jdx/ruby's".

> You know how to weight the costs and benefits.

[re: asked to choose between raising the macOS floor to 26, which taking the Mac's Ruby from jdx/ruby costs, and Fledge building and keeping an OpenSSL of its own for the Mac.]

*Governs:* the weighing of the macOS floor against a Fledge-built OpenSSL was the agents' to do. They chose the floor of 26, with his earlier leave to raise it ("maybe 26 if it becomes costly to keep it at 15", above). *Applied in:* ADR 100; `doc/contributors/design/releases.md`, "Platform floors".

> Everybody and their brother trusts mise, but Fledge shouldn't?

> > A developer who hears about a fix can upgrade their Ruby in a minute. A person who was handed an app can't.
>
> Even if Fledge cuts their own Rubies, a developer still relies on e.g. our GitHub Actions not being paused/buggy. They rely on a practically-unknown third party (us) or a very famous third party (mise).

[re: the orchestrating agent had found that jdx/ruby, the project whose prebuilt Rubies mise downloads and whose Ruby Fledge's macOS and glibc Linux runtimes take, compiles in OpenSSL 3.5.5 where OpenSSL's newest 3.5 release was 3.5.9, and that nothing in that project updates its libraries by itself.]

> > Fledge's automation must carry every update that reaches it
>
> Isn't that what I said in the first place?

*Governs:* Fledge takes its macOS and glibc Linux Ruby from jdx/ruby and does not build its own for them because that project's libraries lag. Depending on a widely used project is preferred to depending on Fledge's own unproven build automation. The lag is a stated dependency, the same every mise user has. *Applied in:* ADR 100; `doc/contributors/design/runtimes.md`, "Why Fledge builds no Ruby for macOS and glibc Linux".

> > Nothing says whether the candidate may carry the Ruby preview or must wait for Ruby 4.1.0. The docs say 1.0 waits for it.
>
> 1.0.0 waits for it, but the 0.X.Y that serves as the release candidate does NOT wait for it. In an ideal world, one where nothing between the dev ruby on the day 0.X.Y releases breaks Fledge, Fledge has no changes between 0.X.Y an 1.0.0 except pointing at the Ruby 4.1.0 release on Christmas Day. (In the real world, there are likely a couple tweaks as new daily builds arrive.)

*Governs:* the release that serves as the candidate carries whatever Ruby the runtimes carry on the day it is cut, today Ruby 4.1's preview, and RubyInstaller's head build on Windows. 1.0.0 waits for Ruby 4.1.0, whose release Ruby expects on Christmas Day, as every year's. Between the candidate and 1.0.0 nothing is meant to change but the pin to Ruby 4.1.0 and what newer builds of Ruby force. *Applied in:* `doc/contributors/design/releases.md`, "Versions" and "The day Ruby 4.1.0 appears".
