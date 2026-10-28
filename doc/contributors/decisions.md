<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

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

*Governs:* the gem's distribution, forever. *Applied in:* AGENTS.md, Releasing; `fledge.gemspec`'s `allowed_push_host`; ADR 001, section 7.

> The walking skeleton must walk on macOS, Windows, and Linux.

*Governs:* the scope of Plan 001 and the Delivery jobs. *Applied in:* Plan 001; `.github/workflows/ci.yml`.

> High quality, tests, linters.

*Governs:* the gate and how work is tested. *Applied in:* AGENTS.md, How to work, Commands, and Definition of done.

## 2026-10-26

Answers to the numbered entries of an earlier `questions.md`. Each answer names, in brackets, what the entry asked when the answer alone does not say.

> 1. Like Tokra (~/Developer/Tokra/), AGPL-3.0-or-later but with SPDX snippets attributing derivative bits of code following the REUSE specification with the reuse tool. We'll likely offer a commercial license (see ~/Developer/setdef.com/) for apps that don't want to follow the AGPL.

*Governs:* the license of everything in this repository, and how code or prose derived from elsewhere is attributed. *Applied in:* AGENTS.md, Licensing; SPDX snippets throughout `runtime/`; `reuse lint` in the gate.

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

*Governs:* the oldest glibc a Linux app runs on. *Applied in:* ADR 001, section 3.

> 8. Because of what I said re: #1, we must be VERY careful to be able to let app devs _not_ be copyleft-laden when they pay for a commercial license.

*Governs:* the license of everything Fledge copies into an app. *Applied in:* AGENTS.md, Licensing (the standing rule for what a runtime may carry); Plan 002, "Copyleft-free runtimes" and "Tell app developers what they owe, from CI."

> 9. When using fledge, your ruby source code should be able to be identical to how it was without Fledge, so the things you had to `require` before you can still need the app dev to `require`, but the things you didn't have to `require` before the app dev still shouldn't have to require.

*Governs:* what a runtime ships and what the launcher does to Ruby's state. *Applied in:* ADR 003; the parity check (`tasks/parity.rb`, run in CI on every platform); `RuntimeBuilder` keeping every default and bundled gem.

> 10. All the ruby globals should be non-surprising to app devs, for the same motivation as #9.

*Governs:* `$0`, `$LOAD_PATH`, `$LOADED_FEATURES`, and every other global an app sees. *Applied in:* ADR 003; the launcher (no `-I`, no `--yjit`); the parity check.

> 11. I don't understand what I'd be deciding here. [re: restoring the person's own RUBY*/GEM*/BUNDLE* env for child processes — orchestrator is explaining; still open]

*Governs:* nothing yet. *Applied in:* `questions.md`, entry C, which tracks the follow-up. The launcher now restores the person's environment after Ruby boots, as the orchestrating agent directed (ADR 003, section 3).

> 12. Many CI platforms only run on musl for Linux, so I'd like to support it eventually, but it's not a blocker to continuing to iterate. It may be a blocker to 1.0 though.

*Governs:* musl Linux targets. *Applied in:* Plan 002, "musl Linux."

> 13. Again, you invented the help header. Recall the difference between what _I've said_ vs. what's on disk. You need _me_ to second-guess _me_, but you don't need _me_ to second-guess _yourself_.

*Governs:* the `fledge build` surface is the agents' to decide. *Applied in:* AGENTS.md, Questions; ADR 002.

> 14. You wrote the ADRs. Recall the difference between what _I've said_ vs. what's on disk. me/me vs. me/yourself

*Governs:* ADR content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions; ADR 001, section 2 (how a version pins its runtimes).

> 15. You wrote the plans. Recall the difference between what _I've said_ vs. what's on disk. me/me vs. me/yourself

*Governs:* plan content is the agents' to decide and change. *Applied in:* AGENTS.md, Questions; Plan 001 (what hello prints).

> 16. Why is this something I should decide? Isn't this something where there's prior art or an industry standard we can/should follow?

*Governs:* behavior with prior art or a standard is the agents' to decide, citing it. *Applied in:* AGENTS.md, Questions; ADR 002 (launcher errors follow `ruby:` messages and sysexits.h).

> 17. Ideally, fledge developers should have the option to make it so Windows/macOS don't block the use of the app. But not every app dev will have the done the required ceremony with Microsoft and/or Apple.

*Governs:* code signing and notarization: an option for developers who have the credentials, with unsigned builds still working. *Applied in:* Plan 002, "Signing and notarization."

> 18. Would this affect what shows up in the taskbar? task manager? start menu? desktop icons? app window top-left corner and/or title bar? If so, app devs need to be able to control it.

*Governs:* an app's icon, name, and version information on every OS are the developer's to control. *Applied in:* Plan 002, "App identity."

> 19. I don't understand what I'd be deciding here. [re: RubyInstaller signing key expiry — agents own this]

*Governs:* the RubyInstaller signing key is the agents' to manage. *Applied in:* ADR 001, section 3; `runtime/sources.yml`.

> 20. Tiny filesize is not a priority; "my ruby code just works" _is_ a (high) priority.

*Governs:* what runtimes prune: only what no running Ruby code can observe. *Applied in:* ADR 003; `RuntimeBuilder.prune`.

> 21. I don't understand what I'd be deciding here. [re: Windows console code pages and Ctrl-C — agents own this]

*Governs:* console code pages and Ctrl-C on Windows are the agents' to decide. *Applied in:* ADR 003 (the launcher matches `ruby.exe`); the parity check's `chcp 437` run; Plan 002, "Ctrl-C and the console."

> 22. I'd like to support Windows on ARM (and Linux on ARM) eventually, but it's not a blocker to continuing to iterate. It may be a blocker to 1.0 though.

*Governs:* ARM targets. Linux on ARM already ships as `aarch64-linux`. *Applied in:* Plan 002, "Windows on ARM."

> 23. Would this require app devs to have a bunch of `if`s or polymorphic objects used throughout their app to handle the difference? [re: Windows ruby\ vs Unix lib/ layout — answer is no; agents own this]

*Governs:* the internal layout of a runtime is the agents' to decide, as long as app code needs no per-OS branches for it. *Applied in:* ADR 001, section 8.

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

*Governs:* the environment an app and its child processes see. *Applied in:* ADR 003, section 3; `runtime/launcher/unix.c` and `windows.c`; the parity check and Delivery.

> 8 and 24. Remember that LGPL and GPL/AGPL's main differentiator is dynamic linking. Relevant here or not?

> Source offer for... the app? Or the LGPL'ed library? Former won't be liked, latter is fine and normal.

> As long as we're clear about that to app devs, that's great.

[re: libxcrypt on Linux and GMP on Windows, both LGPL. The orchestrator explained that, shipped as separate, replaceable shared libraries, they leave the app proprietary but still require a notice, the library's source or a written offer of it, the ability to replace the library, and app terms that permit reverse engineering for debugging such a replacement (LGPL-2.1 section 6, LGPL-3.0 section 4).]

*Governs:* LGPL components may ship in a runtime only as separate, replaceable shared libraries, never linked statically; Fledge publishes the source of each LGPL library it ships and never requires an app's source or object files; what app developers owe is stated to them plainly. *Applied in:* AGENTS.md, Licensing; Plan 002, "Copyleft-free runtimes" and "Tell app developers what they owe."

> "lists, for each platform, everything that..." Better to automate this as part of the DevOps pipeline, yes?

[re: a user-facing page listing, for each platform, every third-party component that ships in an app, its license, and what the app developer must do.]

*Governs:* the component list, license notices, SBOM, and licensing page are generated from each built runtime in CI, behind a license policy gate, never written by hand. *Applied in:* Plan 002, "Tell app developers what they owe."

## 2026-10-27

> We should, if we can, support iOS and iPadOS and Android. Ideally before 1.0 but I could be swayed if it turns out incredibly burdensome.

[re: whether Fledge should target iOS, iPadOS, and Android, which Lota's session raised after the maintainer asked for Lota games on those platforms. The orchestrator had noted that mobile changes Fledge's model: a build step inside Xcode or Gradle, Ruby linked statically with no JIT, and mandatory store rules.]

*Governs:* mobile targets are in scope, aimed at 1.0, unless a spike shows them incredibly burdensome. *Applied in:* Plan 002, "iOS, iPadOS, and Android"; `doc/contributors/research/2026-10-27-mobile.md`.

> Would it be a good idea to move that research somewhere more durable for cross-session reference? Maybe the repo?

*Governs:* research that sessions share lives in the repository, under `doc/contributors/research/`. *Applied in:* `doc/contributors/research/`.
