<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

## Project

Fledge (the `fledge` gem, https://github.com/setdef/Fledge) ships a Ruby app to people who don't have Ruby. It copies an app, the program its developer already runs (`exe/my_cool_app`, `bin/server`, or a `main.rb`) with its project and the gems its Gemfile.lock locks, into the runtime for the platform it runs on: a relocatable CRuby plus a small C launcher that embeds it and runs the program, with Bundler set up as `bundle exec` would (ADR 005). Then it archives the result. Runtimes are prebuilt per platform by Fledge's own CI (ADR 001), and each platform's app is built on a computer of that platform, with that platform's own tools (ADR 010). Targets use RubyGems platform names: `arm64-darwin`, `x86_64-linux`, and `x64-mingw-ucrt` to start. App kinds are `console` and `windowed`: a windowed app is an `.app` bundle on macOS, signed ad hoc, a GUI program on Windows, and a folder with a desktop entry on Linux, and every app carries the name, icon, version, and identifier its `fledge.yml` gives, where each system shows them (ADR 008); a windowed app also gets its platform's installer, a `.dmg`, an NSIS setup program, or an AppImage (ADR 009). Framework wrappers (Lota for 2D games, Tokra for desktop apps, Rooibos for terminal UIs) will call Fledge. The plans of record are `doc/contributors/plan/001.md` (the walking skeleton) and `doc/contributors/plan/002.md` (toward 1.0); what the maintainer has decided is in `doc/contributors/decisions.md`.

Pre-1.0, zero external users. Prefer good design over backward compatibility; record every breaking change in CHANGELOG.md.

## Design precedence

1. **A person who double-clicks or runs the app never meets Ruby.** No install step, no Ruby on `PATH`, no error that names a gem, no influence from a Ruby the person happens to have (`RUBYLIB`, `RUBYOPT`, `GEM_HOME`, and the rest are hidden from Ruby's boot, and the app's gems are the runtime's). When anything below conflicts with this, this wins.
2. **The app's Ruby code runs as it does under `ruby main.rb`, or `bundle exec`.** Same requires, same globals, same `ENV`, same standard library, bundled gems, and locked gems (decisions 9, 10, and 20; ADR 003 and ADR 005). The parity check proves it on every platform; a difference is a bug unless `Parity::JUSTIFIED` says why it is right.
3. **Ruby the language and its own conventions.** RubyGems platform names for targets, CRuby's own `main.c` for how the launcher starts the interpreter, Ruby's own layout for the standard library. Read the source at the pinned Ruby version; do not guess.
4. **Prior art and standards.** GNU's and POSIX's command-line conventions, sysexits.h, and LÖVE's fused games (an app is a folder joined to a runtime), the Tauri bundler, PyInstaller and Briefcase (console and windowed kinds), and python-build-standalone (prebuilt relocatable interpreters). When Fledge needs a behavior these already settled, match them and cite them in an ADR.
5. **Ruby culture.** Idioms yield to 1 through 4.

## How to work

- Research before designing: read the relevant ADR in `doc/contributors/adr/` and the prior art's source or documentation first. Never guess at a reference's contents; cite the file and lines you relied on.
- Root-cause every fix. If you cannot explain why a change fixed the symptom, it is not a fix.
- Write tests first. A test must fail if the code it covers is deleted or mutated, and must exercise real collaborators, not stubs that hide missing behavior. The CLI is tested through real streams (injected `StringIO`) and as a subprocess; the walking skeleton's acceptance test is a built app run on a fresh machine with no Ruby (Plan 001).
- Code is a liability (decisions, 2026-10-28). Never write a file format, archive, image codec, signer, or other tool Fledge can get from a maintained, pinnable existing tool or gem; use the tool, built or run on the platform it belongs to. Write code only for what no such tool does, and say in the ADR which tools were considered and why none fit.
- Each target is built on its own operating system, with that system's tools, as Tauri, Electron's tooling, and Briefcase build; Fledge does not build one platform's app on another (decisions, 2026-10-28).
- Pin every external input (Ruby builds, actions, tools) by version and, where it is downloaded, by SHA-256. Updates arrive on purpose.
- Design in the spirit of Kent Beck (small steps, Implementation Patterns), Freeman & Pryce (tests drive interfaces), Sandi Metz (duplication over the wrong abstraction), Rebecca Wirfs-Brock (responsibility-driven roles), Martin Fowler (refactor in behavior-preserving steps), and Matz (programmer happiness). Write prose in the style of `doc/contributors/documentation_style.md`.

## Ruby, RBS, and docs

- `Data.define` for value objects (`class Foo < Data.define(...)`), `class` for entities.
- Every Ruby method has an RBS signature in `sig/` mirroring `lib/`. No `untyped`, no comments in `.rbs`. For `Data.define` classes, declare `self.new` instead of `initialize` (Steep mis-checks `initialize` there); plain classes declare `initialize` as usual.
- RDoc (never YARD) in `.rb` files only. Wrap SPDX headers in `#--` / `#++`, and wrap examples in `MIT-0` SPDX snippets.
- The help `fledge --help` prints is the comment header in `exe/fledge`, between the `####` and `###` lines. Change the CLI and that header together.
- Architectural decisions get an ADR; plans live in `doc/contributors/plan/`.

## Commands

- Run Ruby with `bundle exec ruby`. Run tests with `bundle exec rake test`. Never `ruby -Ilib:test`.
- `bundle exec rake` is the gate: RuboCop and REUSE fixes, tests, RuboCop, RubyCritic, RDoc coverage, REUSE, actionlint and shellcheck, RBS checks (no `untyped`, `rbs validate`, signature parity), Steep, and the package check. It must pass with zero errors and zero warnings. Run `bundle exec rake rubocop:autocorrect_all` first to save time.
- RubyCritic reports a score and a rating for each file and fails nothing, as in Tokra and rove_2d. Its score is an average of each file's complexity, which code that reads and writes binary formats runs high on however it is designed, so a floor would reward splitting files over making them clear. Read its report after a change instead: no file in `lib/` may be rated F, and when one falls toward it, find the responsibility it took on and give that a class of its own.
- Approved exceptions live in `rbs_exceptions.rb`; adding one needs a justification that it is impossible otherwise.
- Rake tasks use `git ls-files`: new or deleted files must be staged before they count.
- `bundle exec rake parity` compares an app built from this computer's runtime with `ruby main.rb` on the Ruby that runtime came from, and a gem-shaped one with `bundle exec` (ADR 003 and ADR 005); run it after `bundle exec rake runtime`. CI runs it on every platform.
- Always `PAGER=cat` for git.

## Provenance

The maintainer uses three words for how work comes to exist. *Written* means typed by hand, with nothing generated. *Wrought* means an agent generated it while the maintainer iterated with it and reviewed every change before committing it. *Requested* means an agent built it with little or no review.

- **In Fledge, everything is requested:** ADRs, plans, this file, the README, `lib/`, `sig/`, `exe/`, `tasks/`, `test/`, the launcher's C, the workflows. Nothing here is written or wrought. Because no one reviews this work line by line, the gates review it, and Delivery most of all: a built app run on a fresh machine that has never seen Ruby. Never weaken a gate to make requested work pass.
- **The maintainer's words** are in `doc/contributors/decisions.md`, quoted verbatim with the date. That file is the only record of what the maintainer said. Everything else here, ADRs, plans, and this file included, was written by agents, and agents change it freely, as long as it stays true to `decisions.md`.
- **Generated code** is marked as generated in its header and is never edited by hand; change the generator instead.

Every commit carries a `Provenance: requested` trailer.

## Questions

`doc/contributors/questions.md` holds only two kinds of question:

1. An apparent conflict with, or ambiguity in, `doc/contributors/decisions.md`.
2. Direction only the maintainer can give: product scope, what app developers control, licensing and commercial terms, money, and external accounts (Apple, Microsoft, certificate authorities, package registries).

Everything agents invented is the agents' to decide: ADR and plan content, CLI details, the help header, error messages, internal layouts, and names inside the runtime. Decide it by prior art and industry standards (Design precedence, above), record the rationale and citations in an ADR, and change it freely when a better reason arrives. Never ask the maintainer to second-guess an agent's own invention; ask only where the maintainer's own words leave something open.

A question names its context, the default the work proceeds on, and how to reverse that default. Do not wait for an answer: build on the default. When the maintainer answers, add the answer verbatim to `decisions.md`, apply it, and remove the question.

## Licensing

Fledge is AGPL-3.0-or-later (decision 1), and setdef may offer it under a commercial license too, so every line must be clearly Fledge's own or clearly attributed.

- **Derived code and prose get SPDX snippets**, as Tokra does (`~/Developer/Tokra`, for example `plugins/notification/test/support/notification_test.rb` and `ext/tokra/src/responders.rs`). Anything adapted from elsewhere (Ruby's `main.c`, `ruby.c`, or `win32/win32.c`; RubyGems; RubyInstaller; rv-ruby; Lota; Tokra; a spike) sits between `SPDX-SnippetBegin` and `SPDX-SnippetEnd`, with the source's `SPDX-License-Identifier`, an `SPDX-SnippetCopyrightText` naming the source's authors, and an `SPDX-SnippetComment` naming the source file and the commit or tag it came from. Do this for the maintainer's own projects too: their license or ownership may differ from Fledge's. Add the source's license text to `LICENSES/`; `reuse lint` in the gate checks both.
- **Nothing Fledge itself puts into an app, its runtime, may carry copyleft obligations beyond keeping notices** (decision 8), except Fledge's own setdef-owned code, which is AGPL-3.0-or-later and commercially licensable. A developer who buys a commercial license must be able to ship an app with no copyleft obligation from Fledge at all. Every third-party component in a runtime (a library, a DLL, a gem, a data file) must be under a permissive license such as MIT, BSD, Apache-2.0, Zlib, or Ruby's; or be an LGPL library shipped as a separate shared library a person can replace, with its source published beside the runtime; or be an LGPL library linked into another component of the runtime that is not Fledge's own, with that component's source and the library's both published beside the runtime (libfuse in AppImage's runtime, which only installers carry; ADR 010); or be under a license that asks only that its source be published (CPL-1.0, NSIS's LZMA module), with its source published beside the runtime. Fledge never asks an app developer for their app's source or object files. GPL or AGPL third-party code in a runtime, and LGPL code linked into Fledge's launcher or into any binary whose source Fledge does not publish, are bugs to remove (Plan 002, "Copyleft-free runtimes"). This policy applies to Fledge's runtimes only. **The gems an app depends on are the app developer's choice and responsibility, licenses and all** (2026-10-28; ADR 007): `fledge build` never refuses, warns about, or annotates a gem for its license, for what its binaries compile in, or for declaring no license; it refuses a gem only when it would not run where the app goes (no build for the target, a checksum or pin that does not match, a Ruby it does not support, a library its compiled files need that nothing provides). Check a new component's license before it lands in `runtime/sources.yml`, and record it, its license, and its notice in `runtime/licenses.yml`: every runtime build runs the license audit against that file and refuses to archive a runtime with anything it does not account for (ADR 004). What the runtime asks of app developers reaches them through the generated `notices/NOTICES.txt` and `doc/licensing.md`; regenerate the page with `bundle exec rake "licensing[DIR]"` when CI says it is stale, and change its generator, `tasks/licensing_page.rb`, never the page.

## Committing

- Commit on `trunk` in coherent steps, each after the gate passes, with the plan, ADR, or question each step produced.
- Pushing `trunk` to `origin` (github.com/setdef/Fledge) is allowed once the gate passes. Never force-push, and never push or tag in any other repository, or to another agent's branch.
- Conventional Commits, plain text, wrapped at 72. The body explains why this approach over alternatives, in prose (no lists, no markdown, no file inventories). Types: `lib`/`sig`/`exe`/launcher feat/fix/refactor/perf; `bin`/`tasks`/CI chore; `examples/` and `doc/` docs; `test/` test. End with the `Provenance: requested` trailer, then the AI footer shown by `git log -n1`.

## Releasing

Before 1.0, agents may push `trunk`, create and push tags (`vX.Y.Z`), and create GitHub Releases (decision 6). Releases are git tags and GitHub Releases at https://github.com/setdef/Fledge, which carry the prebuilt runtimes as assets, as Ferro releases by tag; `.github/workflows/release.yml` publishes one when a tag is pushed, after CI passes, with each runtime's SBOM, NOTICES, and LGPL source bundle beside it, and then `installed.yml` installs Fledge from the tag and delivers hello with the published runtimes. Tag only a commit whose CI is green on every job, and never delete a release: each runtime's NOTICES links its LGPL source bundle there.

Fledge never publishes to RubyGems.org: no `gem push`, ever, by anyone working in this repository. The gemspec's `allowed_push_host` points nowhere, and `rake release` refuses.

## Changelog

Keep a Changelog + SemVer. Only changes people who build apps with Fledge, or run apps built with it, can observe: the CLI, behavior, what a built app contains, breaking changes, deprecations, dependency changes (including the pinned Ruby versions and their sources). Not tests, docs, internal refactors, or tooling. Terse one-line entries under `## [Unreleased]`, which means "since the last tag": a change undone before the next tag removes its entry instead of adding a "Fixed" line. Never edit released sections.

## Definition of done

1. Every item in the plan is done, or explicitly deferred with a reason.
2. Behavior follows the design precedence above; deviations from the prior art are justified and documented.
3. `bundle exec rake` passes from a clean build (`rm -rf tmp`), zero errors, zero warnings.
4. RDoc, RBS, the `exe/fledge` help header, `doc/`, README, and CHANGELOG updated where behavior changed.
5. The work is true to `doc/contributors/decisions.md`, and any conflict or open direction is in `doc/contributors/questions.md`.
6. A commit message is written (and the commit made, per Committing).
