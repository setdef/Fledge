<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Maintainer's Decisions

This file records what the maintainer has said, word for word, and nothing else. It is the source of truth for "what the maintainer decided." Everything else in this repository (the ADRs, the plans, the help header, the error messages, the layouts, this file's notes) was written by agents, and agents may change it, as long as it stays true to what is quoted here (AGENTS.md, Provenance).

His words are the blockquotes. When he quoted a sentence with `>`, that sentence is part of his words, kept inside the quotation exactly as he typed it. Under a quotation, an agent notes what it governs and where it is applied, and a "[re:" line says what his words refer to when they do not say. When a quotation and a note disagree, the quotation wins. When a quotation seems to conflict with another, or is ambiguous, ask in `questions.md`; never guess.

## From the original session

The project was started with these directions, given in prose rather than as a numbered list. They are quoted as the orchestrating agent relayed them from that session.

> Fledge is requested.

*Governs:* how every piece of work here comes to exist. *Applied in:* AGENTS.md, Provenance.

> Agents may push to trunk.

*Governs:* where agents put their work. *Applied in:* AGENTS.md, Committing.

> Never publish to RubyGems.org.

*Governs:* agents never publish the gem to RubyGems.org. *Applied in:* AGENTS.md, Releasing; `fledge.gemspec`'s `allowed_push_host`; `doc/contributors/design/releases.md`, "Where releases are".

> The walking skeleton must walk on macOS, Windows, and Linux.

*Governs:* the scope of the first plan. *Applied in:* Plan 001; `.github/workflows/ci.yml`.

> High quality, tests, linters.

*Governs:* the gate and how work is tested. *Applied in:* AGENTS.md, How to work, Commands, and Definition of done.

## 2026-10-26

Answers to the numbered entries of an earlier `questions.md`. Each answer names, in brackets, what the entry asked when the answer alone does not say.

> 2. What are the other options? [re: "an app is a folder with a main.rb" — still open]

*Governs:* nothing; he asked a question back, which the first reply below answers.

> 3. None at all, for now. I'll tackle Provenance before releasing 1.0. [re: the provenance statement under exe/fledge's help header]

*Governs:* `exe/fledge` carries no provenance statement. *Applied in:* `exe/fledge`; `test/cli_test.rb`.

> 4. What is the GNU standard? What is the Unix standard? What would Windows users expect? [re: -V and bare-fledge behavior]

*Governs:* agents follow the standards rather than ask (see decision 16). *Applied in:* `doc/contributors/design/public-interface.md`, "The command's conventions".

> 5. You invented the help header, so that's a problem you created. My instinct is to use the app's primary class/module's name, like MyCoolApp. [re: NAME in dist/NAME-PLATFORM — depends on #2, still open]

*Governs:* his instinct is that NAME is the app's primary class or module name.

> 6. Before the release of 1.0, you may push to trunk and you may create and push tags and you may create github releases, but you may not release to rubygems.

*Governs:* what agents may publish before 1.0. *Applied in:* AGENTS.md, Committing and Releasing; `.github/workflows/release.yml`.

> 7. 2.39 is fine, and even newer may be fine if there becomes good reason to raise the floor.

*Governs:* the oldest glibc a Linux app runs on. *Applied in:* ADR 100; `doc/contributors/design/releases.md`, "Platform floors".

> 8. Because of what I said re: #1, we must be VERY careful to be able to let app devs _not_ be copyleft-laden when they pay for a commercial license.

*Governs:* no third-party component of a runtime may leave an app's developer with copyleft obligations beyond notices; since 2026-11-07, when Fledge became MIT, it stands without "#1" and the commercial license, and it does not reach the app's own gems (2026-10-28). *Applied in:* AGENTS.md, Licensing; Plan 002, "Copyleft-free runtimes" and "Tell app developers what they owe, from CI."

> 9. When using fledge, your ruby source code should be able to be identical to how it was without Fledge, so the things you had to `require` before you can still need the app dev to `require`, but the things you didn't have to `require` before the app dev still shouldn't have to require.

*Governs:* what a runtime ships and what the launcher does to Ruby's state. *Applied in:* ADR 081; `doc/contributors/design/runtimes.md`, "What a runtime keeps"; `tasks/parity.rb`.

> 10. All the ruby globals should be non-surprising to app devs, for the same motivation as #9.

*Governs:* `$0`, `$LOAD_PATH`, `$LOADED_FEATURES`, and every other global an app sees. *Applied in:* ADR 081; `tasks/parity.rb`.

> 11. I don't understand what I'd be deciding here. [re: restoring the person's own RUBY*/GEM*/BUNDLE* env for child processes — orchestrator is explaining; still open]

*Governs:* nothing; the next section answers it.

> 12. Many CI platforms only run on musl for Linux, so I'd like to support it eventually, but it's not a blocker to continuing to iterate. It may be a blocker to 1.0 though.

*Governs:* musl Linux targets. *Applied in:* Plan 002, "musl Linux."

> 13. Again, you invented the help header. Recall the difference between what _I've said_ vs. what's on disk. You need _me_ to second-guess _me_, but you don't need _me_ to second-guess _yourself_.

*Governs:* the `fledge build` surface is the agents' to decide. *Applied in:* AGENTS.md, Questions.

> 14. You wrote the ADRs. Recall the difference between what _I've said_ vs. what's on disk. me/me vs. me/yourself

*Governs:* ADR content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions.

> 15. You wrote the plans. Recall the difference between what _I've said_ vs. what's on disk. me/me vs. me/yourself

*Governs:* plan content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions.

> 16. Why is this something I should decide? Isn't this something where there's prior art or an industry standard we can/should follow?

*Governs:* behavior with prior art or a standard is the agents' to decide, citing it. *Applied in:* AGENTS.md, Questions; `doc/contributors/design/launcher.md`, "Messages and exit statuses".

> 17. Ideally, fledge developers should have the option to make it so Windows/macOS don't block the use of the app. But not every app dev will have the done the required ceremony with Microsoft and/or Apple.

*Governs:* code signing and notarization are an option for developers who have the credentials, with unsigned builds still working. *Applied in:* Plan 002, "Signing and notarization."

> 18. Would this affect what shows up in the taskbar? task manager? start menu? desktop icons? app window top-left corner and/or title bar? If so, app devs need to be able to control it.

*Governs:* an app's icon, name, and version information on every OS are the developer's to control. *Applied in:* Plan 002, "App identity."

> 19. I don't understand what I'd be deciding here. [re: RubyInstaller signing key expiry — agents own this]

*Governs:* the RubyInstaller signing key is the agents' to manage. *Applied in:* ADR 100; `doc/contributors/design/runtimes.md`, "The RubyInstaller signing key".

> 20. Tiny filesize is not a priority; "my ruby code just works" _is_ a (high) priority.

*Governs:* a runtime prunes only what no running Ruby code can observe. *Applied in:* `doc/contributors/design/runtimes.md`, "What a runtime keeps" and "What a runtime prunes, and why nothing reads it".

> 21. I don't understand what I'd be deciding here. [re: Windows console code pages and Ctrl-C — agents own this]

*Governs:* console code pages and Ctrl-C on Windows are the agents' to decide. *Applied in:* ADR 081; `doc/contributors/design/launcher.md`, "The locale"; Plan 002, "Ctrl-C and the console."

> 22. I'd like to support Windows on ARM (and Linux on ARM) eventually, but it's not a blocker to continuing to iterate. It may be a blocker to 1.0 though.

*Governs:* ARM targets. *Applied in:* Plan 002, "Windows on ARM."

> 23. Would this require app devs to have a bunch of `if`s or polymorphic objects used throughout their app to handle the difference? [re: Windows ruby\ vs Unix lib/ layout — answer is no; agents own this]

*Governs:* a runtime's internal layout is the agents' to decide, as long as app code needs no per-OS branches for it. *Applied in:* `doc/contributors/design/runtimes.md`, "Layout on Windows".

> 24. See #8 [re: GMP being LGPL]

*Governs:* GMP, like every other component of a runtime, falls under decision 8. *Applied in:* Plan 002, "Copyleft-free runtimes."

## 2026-10-26, later

Replies to the orchestrating agent's answers in chat, quoted from the maintainer's messages. The orchestrating agent recorded them, because the maintainer, asked whether it could, said "You may" (2026-10-27). Brackets say what each reply answered.

> 2. Ok.

[re: the orchestrator's recommendation: ship the executable you already run, with the project root where the Gemfile or gemspec is, and NAME taken from the project's name]

*Governs:* an app's entry point is the executable it already runs, and NAME comes from the project, which configuration can override. *Applied in:* Plan 002, "Ship the executable you already run."

> 4. Ok.

[re: `-h`, `-?`, `--help`, `-v`, and `--version` print to standard output and exit 0; a usage error prints to standard error and exits 2]

*Governs:* the CLI conventions. *Applied in:* `doc/contributors/design/public-interface.md`, "The command's conventions".

> 11. I think yes?

[re: restoring the person's own `RUBYOPT`, `GEM_*`, `BUNDLE_*`, and the rest into `ENV` after Ruby has booted]

*Governs:* after Ruby boots, an app and its child processes see the person's own Ruby environment variables. *Applied in:* `doc/contributors/design/launcher.md`, "Hiding and restoring the person's Ruby settings"; `runtime/launcher/unix.c`; `runtime/launcher/windows.c`.

> 8 and 24. Remember that LGPL and GPL/AGPL's main differentiator is dynamic linking. Relevant here or not?

> Source offer for... the app? Or the LGPL'ed library? Former won't be liked, latter is fine and normal.

> As long as we're clear about that to app devs, that's great.

[re: libxcrypt on Linux and GMP on Windows, both LGPL, shipped as separate shared libraries]

*Governs:* an LGPL library may ship in a runtime as a separate shared library with its own source offered, never the app's, and app developers are told plainly what they owe; it governs Fledge's runtimes, not the app's own gems (2026-10-28). *Applied in:* AGENTS.md, Licensing; Plan 002, "Copyleft-free runtimes" and "Tell app developers what they owe, from CI."

> "lists, for each platform, everything that..." Better to automate this as part of the DevOps pipeline, yes?

[re: a page listing each platform's third-party components, their licenses, and what the app developer must do]

*Governs:* that page is generated in CI, not written by hand. *Applied in:* Plan 002, "Tell app developers what they owe, from CI."

## 2026-10-27

> We should, if we can, support iOS and iPadOS and Android. Ideally before 1.0 but I could be swayed if it turns out incredibly burdensome.

*Governs:* mobile targets are in scope, aimed at 1.0, unless they prove incredibly burdensome. *Applied in:* Plan 002, "iOS, iPadOS, and Android"; `doc/contributors/research/2026-10-27-mobile.md`.

> Would it be a good idea to move that research somewhere more durable for cross-session reference? Maybe the repo?

[re: the mobile research]

*Governs:* he proposed keeping research that sessions share in the repository. *Applied in:* `doc/contributors/research/`.

## 2026-10-28

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> Why does it refuse GPL and AGPL gems? That's up to the app dev to decide, not up to Fledge. In fact, why is Fledge taking any kind of opinion at all about what license the gems the app dev uses are under?

[re: `fledge build` refusing GPL and AGPL app gems]

*Governs:* Fledge takes no position on the licenses of the gems an app depends on; they are the app developer's choice and responsibility. *Applied in:* `doc/contributors/design/gems.md`, "Checks that are not about licenses"; AGENTS.md, Licensing; `Fledge::AppGems`; `Fledge::Linkage`; `doc/licensing.md`, "Your app's own gems"; the README; `exe/fledge`'s help; Plan 002; `test/fixtures/native_app`; `test/fixtures/nokogiri_app`.

> We should eventually get an Apple Developer account, but I'd like to wait until the last responsible moment.

[re: an Apple Developer account and real devices, for testing and App Store submission. Asked whether to record this, he said: "Yes, record it in decisions.md."]

*Governs:* agents proceed without an Apple Developer account, and raise it in `questions.md` when a story cannot be done without one. *Applied in:* Plan 002.

> Code is a liability and we should _not_ have 4k+ lines of things we could use existing tools for.

> We already have to have target-environment-platform machines to compile on, right? If so, what value does cross-platform non-compilation building add?

[re: he accepted the orchestrator's recommendation to build each target on its own OS with that OS's maintained tools]

*Governs:* Fledge builds each target on its own OS and uses maintained existing tools rather than code of its own wherever such tools exist; it does not build one platform's app on another. *Applied in:* AGENTS.md, How to work.

## 2026-11-02

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> We can't spend money on this right now.

[re: a device cloud account or an Apple-silicon Mac so CI could run Android's arm64-v8a build]

*Governs:* agents spend no money on Android's arm64-v8a proof. *Applied in:* Plan 003, "Android on arm64"; ADR 099 and ADR 012.

> We can't spend money on this right now.

[re: an Apple Developer account for a real iPhone and iPad, and a Windows code signing certificate or Azure Trusted Signing account]

*Governs:* agents spend no money on those accounts; the stories that need them wait. *Applied in:* Plan 003, "iOS on a real device, and App Review" and "Notarization and real trust chains"; `doc/contributors/design/signing.md`, "What CI proves, and the stand-ins".

## 2026-11-02

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> 1. No 1.0 until at least some of these things are proven. But we can go from A.B.C.pre.D to 0.1.0 sem-ver style.
> 2. We really shouldn't have external dependencies on those repos; they are expected to depend upon us, not the other way around.
> 3. Go for .deb

[re: the numbering is his, answering the orchestrator's briefing; "those repos" are Rooibos's and Tokra's]

*Governs:* 1.0 waits until at least some of the unproven things are proven; releases move to ordinary 0.MINOR.PATCH versions, beginning with 0.1.0; Fledge depends on no wrapper's repository; a `.deb` installer is built. *Applied in:* Plan 003.

> iPadOS, iOS, and Android are our priorities for 0.2.0.

*Governs:* the work for release 0.2.0 is phones: iPadOS, iOS, and Android. *Applied in:* Plan 003.

## 2026-11-02, later

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> "Never publish to RubyGems.org" was an instruction to agents (for AGENTS.md) not a position the project takes; even when the library is on RubyGems.org I'll continue to make that a human-only activity.

*Governs:* publishing to RubyGems.org is a human-only activity, whether or not Fledge is on it; "Never publish to RubyGems.org" binds agents and is not a position of the project, so documents for developers do not say Fledge is never published there. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`, "Where releases are".

## 2026-11-02, later again

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> I use three words for how code and prose comes to exist. Code I wrote, I typed by hand, with nothing generated. Code I wrought, an AI agent generated while I iterated with it, and I reviewed every change before committing it, so I take responsibility for every diff. Code I requested, an agent built with little or no review from me, in the style of a "dark factory."

[re: he then wrote: "You can drop "or prose" from it." The three "or prose" are left out above.]

*Governs:* what *written*, *wrought*, and *requested* mean wherever Fledge uses them. *Applied in:* AGENTS.md, Provenance; the README.

> I want to get to "I can playtest [a game written in Ruby using Lota] on [an M1 iPad Pro running iPadOS 27] and [a OnePlus Nord N30 5G running Android 13]" as the litmus test for "phones and tablets" (0.2.0).

[re: the brackets stand for what the maintainer named]

*Governs:* release 0.2.0 means a Ruby game on Lota can be playtested on an iPad and on an Android phone, built through Fledge. *Applied in:* Plan 003, "A game plays on a tablet and a phone".

> Remember: this entire rule is because _Fledge should never surprise an app dev with how it behaves or causes Ruby or its globals, built-ins, and standard library to behave compared to not using Fledge_.

[re: Design precedence 2]

*Governs:* the purpose of Design precedence 2 and of the parity check: a difference from the same program run without Fledge is a bug unless it is justified and documented. *Applied in:* AGENTS.md, Design precedence 2; `doc/contributors/design/launcher.md`, "bin/ruby and restarts".

## 2026-11-03

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> Once we hit 1.0.0, we will be releasing via RubyGems (human only), not relying on GitHub Releases and git tags.

*Governs:* from 1.0.0, Fledge is also released on RubyGems.org, by a human; before it, only by git tag and GitHub Release (his explanation of 2026-11-04, below). *Applied in:* Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0"; AGENTS.md, Releasing.

> I can buy that for now, but will easily be swayed by the first app dev who gets upset by the deviation. And we shouldn't be cagey about it or hide it.

[re: the launcher's turning a bare C locale into a UTF-8 one]

*Governs:* the locale coercion stays until the first app developer reports it as a surprise, then it is reversed; any deviation from plain Ruby is documented plainly where app developers read. *Applied in:* the README; `doc/contributors/design/launcher.md`, "The locale"; `Parity::JUSTIFIED`.

> A minor release can make additional rubies available, but can only change the defaults' patch versions--unless we abandon the concept of default entirely, and require app devs to specify a version (maybe better?); then it's limited to e.g. generated config files, which can change in a minor version because they don't get re-generated on upgrade.
>
> Ruby doesn't follow SemVer, so 4.1 is expected to have breaking changes from 4.0.
>
> I require a major version bump to drop support for a ruby, or to drop support for an OS "version" (the thing that differentiates MacOS 26 from MacOS 27, not patches etc.).

*Governs:* a minor release may add Rubies and change only a default Ruby's patch version, and dropping a Ruby, or an operating system version (macOS 26 against 27, not a patch), requires a major version. *Applied in:* `doc/contributors/design/releases.md`, "Versions" and "Ruby minors and runtimes"; `doc/contributors/design/public-interface.md`.

> We'll be reusing the git/ruby version stuff from RatatuiRuby and Rooibos. How tags work (and release branches, backports, etc.) differ before and after 1.0.0.

*Governs:* Fledge's versioning, tagging, release branches, and backports reuse RatatuiRuby's and Rooibos's, and differ before and after 1.0.0; the tooling waits on its extraction (2026-11-07, below). *Applied in:* `doc/contributors/design/releases.md`, "Versions" and "From 1.0: release branches and a human publishing"; Plan 003, "1.0".

> winget, Chocolatey, Scoop, brew, apt-get, pacman, dnf, etc. are all very relevant for Ruby console apps.

*Governs:* package managers are in scope for Fledge's console apps. *Applied in:* `doc/contributors/research/2026-11-04-app-stores.md`; Plan 003.

## 2026-11-04

He wrote this about the sentence of 2026-11-03 above. It is quoted in part: the dictionary definitions of "rely", "dependent", "require", and "necessity" that followed it are left out.

> > Once we hit 1.0.0, we will be releasing via RubyGems (human only), not relying on GitHub Releases and git tags.
>
> Prior to 1.0.0, this gem would not release via RubyGems by using `gem push`. This is because prior to 1.0.0 I don't know if it'll succeed and I don't want to be a name squatter with a failed project.
> Both before and after 1.0.0, it is expected that, like RatatuiRuby before, all releases will be findable via git tags in the source repos, which automatically become GitHub Relaeses.
> Only before 1.0.0, that is the _only_ way they'll be findable, so releases **rely** on GitHub Releases / git tags.
> After 1.0.0, that is _one way_ they'll be findable, so releases do not **rely** on GitHub Releases / git tags, they can be found another way too.

*Governs:* nothing is pushed to RubyGems.org before 1.0.0; every release has its git tag and the GitHub Release made from it; from 1.0.0 a release is also on RubyGems.org. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`, "Where releases are" and "From 1.0: release branches and a human publishing"; `doc/contributors/design/public-interface.md`, "Frozen for 1.x"; Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0".

> > "may an agent open a free account on a second host?"
>
> Absolutely not. If you want a second host, you come to me asking (optionally with suggestions).

*Governs:* an agent never opens an account, free or paid, on any service; when one is wanted, it asks the maintainer, with suggestions. *Applied in:* AGENTS.md, Questions.

> One third of the reason Fledge exists is to support Lota, which is a faithful port of LÖVE2D to Ruby. Drag-to-fuse is a huge part of why LÖVE2D is successful; CLIs can be scary to newbies.

*Governs:* drag-to-fuse, as LÖVE's fused games have it, is in scope for Fledge, because supporting Lota is a main purpose of the project. *Applied in:* Plan 003, "Build from a built app, and the files an app opens".

> Question D. My main concern was adding a lot of code, complexity, and surface area for bugs re: cross-compiling. Anything that doesn't do those is fine by me.

[re: whether a repack may make one system's app on another system when it compiles nothing]

*Governs:* making an app for another system from an already built app is allowed when it adds little code, complexity, and room for bugs, and above all needs no cross-compiling. *Applied in:* `doc/contributors/design/desktop-apps.md`, "Building from a built app".

> I've decided to pay Apple, Microsoft, Google, whoever I need.

[re: publishing Dot Popper on the Play Store, App Store, Mac App Store, Windows Store, and brew]

*Governs:* he will pay for the accounts and certificates the stores need, which ends the rulings of 2026-10-28 and 2026-11-02 that no money is spent; an agent still never opens an account. *Applied in:* Plan 003's store and signing stories.

## 2026-11-07

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> setdef now licenses Fledge under the MIT license.

*Governs:* Fledge's own code is MIT, held by setdef; released tags through `v0.7.0` keep the license they were released under. *Applied in:* every file's SPDX header, `LICENSE`, the gemspec, each app's `notices/NOTICES.txt`, the README, AGENTS.md, Licensing.

> In fact, I specifically said that ratatui_ruby-devtools is in the middle of being extracted and after that work is done by those agents we'll need to further extract the non-RatatuiRuby-ecosystem parts of it to reuse for Fledge, lota, etc.

> Only if I explicitly instruct it.

[re: the second line answers whether Fledge's agents may do the second extraction; he had just written: "I never said you may port RatatuiRuby's release tooling."]

*Governs:* Fledge's release tooling waits until RatatuiRuby's agents finish extracting `ratatui_ruby-devtools` and its non-RatatuiRuby parts are extracted again; nothing is ported before then, and Fledge's agents do the second extraction only if he explicitly instructs it. *Applied in:* Plan 003, "Fledge on RubyGems.org, and runtimes that do not depend on one host" and "1.0"; `doc/contributors/design/releases.md`, "From 1.0: release branches and a human publishing".

## 2026-11-08

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> I want this 1.0.0-ready pending only my manual testing (or the testing I need to prompt you to do) that is blocked on my developer accounts.

*Governs:* agents finish everything for 1.0.0 that his developer accounts do not block, and he tests the rest, or prompts an agent to; it does not say which tests must pass before 1.0.0 is tagged. *Applied in:* `doc/contributors/releasing-1.0.md`; `doc/contributors/questions.md`, question C; Plan 003.

> Yes, cut v0.X.Y releases as appropriate as we go along; my ideal is that v0.A.B (where A.B is the highest 0.X.Y release ever made) has the same features/fixes/etc. as v1.0.0 will when it gets cut.

[re: whether to cut v0.10.0 now]

*Governs:* agents release 0.x versions as work accumulates, so that the newest 0.x release has what 1.0.0 will. *Applied in:* AGENTS.md, Releasing; `doc/contributors/design/releases.md`, "Versions".

> Keep a list of account-block tests current and clear for me to work through myself; I may decide at some point which ones I want to keep blocking 1.0.0 and which ones I don't.

*Governs:* agents keep a current, clear list of the tests that wait on his developer accounts; which of them block 1.0.0 is his to choose, later. *Applied in:* `doc/contributors/account-tests.md`; AGENTS.md, Releasing; `doc/contributors/questions.md`, question C.

## 2026-11-09

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> If the Fledge agent and Lota agent agree, I'd rather see Fledge and Lota ship 4.1-preview now, drop 4.0 now, and not ship Fledge 1.0.0 or Lota 1.0.0 until 4.1 releases.

[re: the Lota agent's proposal that Lota and Fledge require Ruby 4.1, previews included]

*Governs:* Fledge's releases carry Ruby 4.1 preview runtimes in place of Ruby 4.0's, Ruby 4.0 is dropped now (but for the one release the next quotation allows), and Fledge 1.0.0 waits for Ruby 4.1.0. *Applied in:* `doc/contributors/design/releases.md`, "Ruby minors and runtimes"; Plan 003, "1.0".

> I am okay with a last-release on Ruby 4.0.9 first, as long as it doesn't meaningfully delay "now". Call it "now-ish" :)

[re: the plan above, with no last release on Ruby 4.0.9]

*Governs:* one last Fledge release on Ruby 4.0.9 is made before the first on Ruby 4.1, as long as it does not meaningfully delay the move to 4.1. *Applied in:* `doc/contributors/design/releases.md`, "Ruby minors and runtimes"; Plan 003, "1.0".

## 2026-11-12

The orchestrating agent received these words first-hand from the maintainer and directed that they be recorded.

> > An MSIX submission: you upload it to Partner Center, and Microsoft signs it during certification. For the Store, you need no code-signing certificate of your own. That's the strongest argument for MSIX.
>
> Very valuable, let's do it if we can.

*Governs:* Fledge builds an MSIX package for a Windows app, if it can, so that a developer can ship through the Microsoft Store without a code-signing certificate of their own.

> > So it's refused because nobody has made it work yet, not because it can't work.
>
> Right, Tauri 2 does phones so it must be possible. If that's the case, we should do it.

[re: gems with Rust extensions on the phones]

*Governs:* gems whose extensions are written in Rust build for iOS and Android, as they do for the desktops.

> > Extensions built without an extconf.rb (a gemspec that names a Rakefile, CMake or configure directly) give Fledge no hook to aim the build at the phone, or to get a static archive out.
>
> Python and other languages that have Fledge-like tools must solve this somehow; so can we.

*Governs:* gems whose extensions build without an `extconf.rb` build for iOS and Android too, as the prior art of other languages' tools does it.

> > ffi gems on phones.
>
> Why can't we have it on both? And why does Fledge leave Ruby's `fiddle` out?

> Yes.

[re: the second quotation answers the offer to start the work]

*Governs:* ffi gems work on iOS and Android, and fiddle is in the iOS runtime.

> > Every platform has justified differences
>
> TRULY justified? Every difference, every lack of parity, is a knife in Fledge's back that could kill the project before it launches.

*Governs:* a difference from `ruby main.rb` is accepted only when it is truly justified; one that could be closed is a bug to fix.

> experiment branches? landing commits? Merge conflicts?
>
> What happened to trunk-based development?

> I don't know why AGENTS.md says that. Read the trunk-based development skill; that's how we should work.

[re: AGENTS.md's rule that a parallel sub-agent never pushes trunk]

*Governs:* every agent works trunk-based as trunkbaseddevelopment.com describes: small green commits pushed straight to `trunk` within minutes, no long-lived or sideways branches, no push to find out whether CI passes, and a red `trunk` reverted at once. *Applied in:* AGENTS.md, Working as an agent.

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
