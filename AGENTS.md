<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

## Project

Fledge (the `fledge` gem, https://github.com/setdef/Fledge) ships a Ruby app to people who don't have Ruby. It copies an app, a folder with a `main.rb`, into a runtime for each target platform: a relocatable CRuby plus a small C launcher that embeds it and runs the app. Then it archives each result. Runtimes are prebuilt per platform by Fledge's own CI, so one machine builds for every platform (ADR 001). Targets use RubyGems platform names: `arm64-darwin`, `x86_64-linux`, and `x64-mingw-ucrt` to start. App kinds will be `console` and `windowed`; the walking skeleton does `console` only. Framework wrappers (Lota for 2D games, Tokra for desktop apps, Rooibos for terminal UIs) will call Fledge. The plan of record is `doc/contributors/plan/001.md`.

Pre-1.0, zero external users. Prefer good design over backward compatibility; record every breaking change in CHANGELOG.md.

## Design precedence

1. **A person who double-clicks or runs the app never meets Ruby.** No install step, no Ruby on `PATH`, no error that names a gem, no influence from a Ruby the person happens to have (`RUBYLIB`, `RUBYOPT`, `GEM_HOME`, and the rest are scrubbed). When anything below conflicts with this, this wins.
2. **Ruby the language and its own conventions.** RubyGems platform names for targets, CRuby's own `main.c` for how the launcher starts the interpreter, Ruby's own layout for the standard library. Read the source at the pinned Ruby version; do not guess.
3. **Prior art.** LÖVE's fused games (an app is a folder joined to a runtime), the Tauri bundler, PyInstaller and Briefcase (console and windowed kinds), and python-build-standalone (prebuilt relocatable interpreters). When Fledge needs a behavior these already settled, match them and cite them.
4. **Ruby culture.** Idioms yield to 1, 2, and 3.

## How to work

- Research before designing: read the relevant ADR in `doc/contributors/adr/` and the prior art's source or documentation first. Never guess at a reference's contents; cite the file and lines you relied on.
- Root-cause every fix. If you cannot explain why a change fixed the symptom, it is not a fix.
- Write tests first. A test must fail if the code it covers is deleted or mutated, and must exercise real collaborators, not stubs that hide missing behavior. The CLI is tested through real streams (injected `StringIO`) and as a subprocess; the walking skeleton's acceptance test is a built app run on a fresh machine with no Ruby (Plan 001).
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
- Approved exceptions live in `rbs_exceptions.rb`; adding one needs a justification that it is impossible otherwise.
- Rake tasks use `git ls-files`: new or deleted files must be staged before they count.
- Always `PAGER=cat` for git.

## Provenance

The maintainer uses three words for how work comes to exist. *Written* means typed by hand, with nothing generated. *Wrought* means an agent generated it while the maintainer iterated with it and reviewed every change before committing it. *Requested* means an agent built it with little or no review.

- **In Fledge, everything is requested:** ADRs, plans, this file, the README, `lib/`, `sig/`, `exe/`, `tasks/`, `test/`, the launcher's C, the workflows. Nothing here is written or wrought. Because no one reviews this work line by line, the gates review it, and Delivery most of all: a built app run on a fresh machine that has never seen Ruby. Never weaken a gate to make requested work pass.
- **Decisions** that belong to the maintainer as product owner go to the maintainer as questions, never as decisions: the public CLI surface (commands, options, output formats), how an app is laid out and configured, the license of anything Fledge copies into the apps people ship, and anything that publishes outside this repository. Do not wait for an answer, and do not decide silently: pick a sensible default that is easy to reverse, build on it, and record the question in `doc/contributors/questions.md` with its context, the default chosen, and how to reverse it. When the maintainer answers, record the answer in an ADR or the plan and remove the question.
- **Generated code** is marked as generated in its header and is never edited by hand; change the generator instead.

Every commit carries a `Provenance: requested` trailer.

## Committing

- One commit per working session, on `trunk`, after the gate passes. Include any plan, ADR, or question the session produced.
- Pushing `trunk` to `origin` (github.com/setdef/Fledge) is allowed once the gate passes. Never force-push, and never push or tag in any other repository.
- Conventional Commits, plain text, wrapped at 72. The body explains why this approach over alternatives, in prose (no lists, no markdown, no file inventories). Types: `lib`/`sig`/`exe`/launcher feat/fix/refactor/perf; `bin`/`tasks`/CI chore; `examples/` and `doc/` docs; `test/` test. End with the `Provenance: requested` trailer, then the AI footer shown by `git log -n1`.

## Releasing

Fledge never publishes to RubyGems.org: no `gem push`, ever, by anyone working in this repository. The gemspec's `allowed_push_host` points nowhere, and `rake release` refuses. Releases are git tags (`vX.Y.Z`) and GitHub Releases, which carry the prebuilt runtimes as assets, as Ferro releases by tag. Cutting a release is the maintainer's call, so it goes to the maintainer as a question.

## Changelog

Keep a Changelog + SemVer. Only changes people who build apps with Fledge, or run apps built with it, can observe: the CLI, behavior, what a built app contains, breaking changes, deprecations, dependency changes (including the pinned Ruby versions and their sources). Not tests, docs, internal refactors, or tooling. Terse one-line entries under `## [Unreleased]`, which means "since the last tag": a change undone before the next tag removes its entry instead of adding a "Fixed" line. Never edit released sections.

## Definition of done

1. Every item in the plan is done, or explicitly deferred with a reason.
2. Behavior follows the design precedence above; deviations from the prior art are justified and documented.
3. `bundle exec rake` passes from a clean build (`rm -rf tmp`), zero errors, zero warnings.
4. RDoc, RBS, the `exe/fledge` help header, `doc/`, README, and CHANGELOG updated where behavior changed.
5. Every maintainer decision the work touched is in `doc/contributors/questions.md` or already answered.
6. A commit message is written (and the commit made, per Committing).
