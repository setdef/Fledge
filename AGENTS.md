<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

This file is binding for every agent that works in this repository. It holds rules and where to look, not the state of the project: the state lives in the files named under Project, and changes with every story.

## Project

Fledge (the `fledge` gem, https://github.com/setdef/Fledge) ships a Ruby app to people who don't have Ruby. It copies the program a developer already runs, with its project and the gems its `Gemfile.lock` locks, into a relocatable CRuby runtime for the platform it runs on, with a small C launcher that starts the program as `bundle exec` would, and archives the result. Each platform's app is built on a computer of that platform, with that platform's own tools. Framework wrappers (Lota, Tokra, Rooibos) call Fledge; Fledge depends on no wrapper's repository.

Pre-1.0, zero external users. Prefer good design over backward compatibility; record every breaking change in CHANGELOG.md.

Where to look:

- `README.md`: what Fledge does today, for app developers.
- `doc/contributors/handoff.md`: where things stand, how to check them, how to release. A session with no memory of earlier ones starts here.
- `doc/contributors/decisions.md`: the maintainer's words. The only authority.
- `doc/contributors/plan/003.md`: the plan of record, after `001.md` and `002.md`, both done.
- `doc/contributors/adr/`: why each part is the way it is. `doc/contributors/design/architecture.md` is the overview, with the index of ADRs and the design documents that say how each part works.
- `doc/contributors/questions.md`: what only the maintainer can answer.

## Design precedence

1. **A person who double-clicks or runs the app never meets Ruby.** No install step, no Ruby on `PATH`, no error that names a gem, no influence from a Ruby the person happens to have (`RUBYLIB`, `RUBYOPT`, `GEM_HOME`, and the rest are hidden from Ruby's boot, and the app's gems are the runtime's). When anything below conflicts with this, this wins.
2. **The app's Ruby code runs as it does under `ruby main.rb`, or `bundle exec`.** Same requires, same globals, same `ENV`, same standard library, bundled gems, and locked gems (decisions 9, 10, and 20; ADR 081, ADR 085, and ADR 086). The parity check proves it on every platform; a difference is a bug unless `Parity::JUSTIFIED` says why it is right. The reason is that Fledge must never surprise an app developer with how Ruby, its globals, built-ins, and standard library behave compared with not using Fledge (decisions, 2026-11-02).
3. **Ruby the language and its conventions.** RubyGems platform names for targets, CRuby's own `main.c` for how the launcher starts the interpreter, Ruby's layout for the standard library. Read the source at the pinned Ruby version; do not guess.
4. **Prior art and standards.** GNU's and POSIX's command-line conventions, sysexits.h, LÖVE's fused games, the Tauri bundler, PyInstaller and Briefcase, and python-build-standalone. When Fledge needs a behavior these already settled, match them and cite them where the behavior is recorded: in the design document that specifies it, or in an ADR when choosing between them was the decision.
5. **Ruby culture.** Idioms yield to 1 through 4.

## How to work

- Research before designing: read the relevant design document, for how a part works, and its ADRs, for why, and the prior art's source or documentation first. Never guess at a reference's contents; cite the file and lines you relied on.
- Root-cause every fix. If you cannot explain why a change fixed the symptom, it is not a fix.
- Write tests first. A test must fail if the code it covers is deleted or mutated, and must exercise real collaborators, not stubs that hide missing behavior. Test the CLI through real streams (injected `StringIO`) and as a subprocess. The acceptance test for a build is a built app run on a fresh machine with no Ruby.
- Code is a liability (decisions, 2026-10-28). Never write a file format, archive, image codec, signer, or other tool that a maintained, pinnable tool or gem already provides; use the tool, built or run on the platform it belongs to. Write code only for what no such tool does, and say which tools were considered and why none fit: in an ADR when choosing between tools was the decision, and otherwise in the design document that specifies the part.
- Build each target on its own operating system, with that system's tools, as Tauri, Electron's tooling, and Briefcase do; Fledge does not build one platform's app on another (decisions, 2026-10-28).
- Pin every external input (Ruby builds, actions, tools, gems) by version and, where it is downloaded, by SHA-256. Updates arrive on purpose.
- Add no requirement the maintainer did not ask for without weighing what it costs, and say what it costs when you propose one.
- Design in the spirit of Kent Beck (small steps, Implementation Patterns), Freeman & Pryce (tests drive interfaces), Sandi Metz (duplication over the wrong abstraction), Rebecca Wirfs-Brock (responsibility-driven roles), Martin Fowler (refactor in behavior-preserving steps), and Matz (programmer happiness). Write prose as `doc/contributors/documentation_style.md` describes.

## Working as an agent

- Proceed through the plan of record without checking in with the maintainer. Decide what is the agents' to decide (Questions, below), record it, and go on to the next story. Come back only when truly blocked.
- A session that orchestrates others delegates each story to a subagent and verifies what the subagent reports before passing it on: its commits with `git log` and `git show`, its CI runs and releases with `gh run view` and `gh release view`. A claim nobody checked is not reported as done.
- No change leaves an ADR or a design document false. A change that departs from an ADR's decision either follows the ADR instead, or comes with a new ADR that records the new decision. A fact an ADR cites as proof that the change makes false (a test, an example, a path) is corrected in the same change. Code that falls short of an ADR on purpose, for now, is a defect: its design document says so, and the fix is the code's.
- Give a subagent the context the work needs, the rules that bind it, and nothing the maintainer did not ask for.
- Work trunk-based (trunkbaseddevelopment.com; decisions, 2026-11-12). Every agent, a subagent working in parallel in its own worktree included, syncs with `trunk`, makes one small change that keeps the build green, runs the gate and proves the change on each platform it touches, syncs again, and pushes `trunk` itself. A rejected push is rebased, proven again, and pushed. Its unpushed commits are its only branch, and they live for minutes, not hours. Work bigger than one commit lands as complete steps, behind a flag or an abstraction, never as a stack held back.
- Integrate only through `trunk`: an agent takes others' work from `trunk`, never from their worktrees or branches. Agents working at once take separate areas, and say which shared code they are about to change before changing it.
- Never push to find out whether CI passes. Only what no computer at hand can run, such as macOS and iOS, is proven in CI before the push, on a short-lived branch whose run keeps every job the change touches. A push that turns `trunk` red is reverted at once, by whoever sees it first, before anything else is done.
- Leave existing `spike/*`, `wip/*`, and `experiment/*` branches alone, and do not delete branches.
- `doc/contributors/decisions.md` holds only the maintainer's meaningful decisions, the ones that shape what Fledge is or does. Corrections, wording changes, and asides go into the document they touch.
- Messages to another project's agent session are brief: what is needed, from which file or commit, and nothing else.

## Ruby, RBS, and docs

- `Data.define` for value objects (`class Foo < Data.define(...)`), `class` for entities.
- Every Ruby method has an RBS signature in `sig/` mirroring `lib/`. No `untyped`, no comments in `.rbs`. For `Data.define` classes, declare `self.new` instead of `initialize` (Steep mis-checks `initialize` there); plain classes declare `initialize` as usual.
- RDoc (never YARD) in `.rb` files only. Wrap SPDX headers in `#--` / `#++`, and wrap examples in `MIT-0` SPDX snippets.
- The help `fledge --help` prints is the comment header in `exe/fledge`, between the `####` and `###` lines. Change the CLI and that header together.
- `lib/fledge/config.schema.json` describes `fledge.yml`. Change `Fledge::Config` and the schema together; a test fails when they disagree.
- An ADR records one architecturally significant decision, between real options, in about a page, as the maintainer's `adr` skill describes. Detailed design, rules, tables, and conventions people consult while working live in `doc/contributors/design/`, and an ADR points there. Code cites an ADR by number for why and a design document by path for how, and no ADR cites a plan. Plans live in `doc/contributors/plan/`.
- Before you edit `README.md` or `README.rdoc`, read both in full, start to finish, not a section found by `grep`. They are one story told twice: the README for people who read it on GitHub, the RDoc for the gem's description. An edit changes what the whole page says, so rewrite the paragraphs it touches until the page reads as one piece, and keep the two files true to each other and to the code. Appending a sentence or a section that the rest of the page does not know about is how those files grew unreadable; do not do it.

## Commands

- Run Ruby with `bundle exec ruby`. Never `ruby -Ilib:test`.
- `bundle exec rake test` runs the unit tests, every test file under `test/` but those in `test/integration/`, in seconds on any computer: run it on the computer you work on, as often as you like. `bundle exec rake test:integration` runs the integration tests, and `bundle exec rake test:all` both, as the gate and CI do. `TEST=test/foo_test.rb` runs one file or glob of either tier (names separated by commas; `N=/pattern/` picks tests by name).
- A unit test takes milliseconds: it builds no runtime and reads none that `rake runtime` built, builds no app that it then runs, compiles nothing, starts no Ruby or script, runs no signing or disk image tool, and reaches no network; a wait in the code under test is passed in short. A test that needs any of these goes in `test/integration/`. CONTRIBUTING.md, "The tests", draws the line.
- An agent's shell runs no hook of `mise activate`, so its `ruby` may not be the one `mise.toml` pins, and Bundler then stops with a stack trace: start every command with `mise x --` (`mise x -- bundle exec rake test`), as CONTRIBUTING.md says.
- `bundle exec rake` is the gate: RuboCop and REUSE fixes, tests, RuboCop, RubyCritic, RDoc coverage, REUSE, actionlint and shellcheck, RBS checks (no `untyped`, `rbs validate`, signature parity), Steep, and the package check. It must pass with zero errors and zero warnings. Run `bundle exec rake rubocop:autocorrect_all` first to save time.
- RubyCritic reports a score and a rating for each file and fails nothing. Read its report after a change: no file in `lib/` may be rated F, and when one falls toward it, find the responsibility it took on and give that a class of its own.
- Approved exceptions live in `rbs_exceptions.rb`; adding one needs a justification that it is impossible otherwise.
- Rake tasks use `git ls-files`: stage new or deleted files before they count.
- `bundle exec rake parity` compares an app built from this computer's runtime with `ruby main.rb` on the Ruby that runtime came from, and a gem-shaped one with `bundle exec`. Run it after `bundle exec rake runtime`. CI runs it on every platform.
- Always `PAGER=cat` for git.

## Provenance

The maintainer uses three words for how code comes to exist (decisions, 2026-11-02, later again). *Written* means the maintainer typed it by hand, with nothing generated. *Wrought* means an AI agent generated it while the maintainer iterated with it, and the maintainer reviewed every change before committing it, so the maintainer takes responsibility for every diff. *Requested* means an agent built it with little or no review from the maintainer, in the style of a "dark factory."

- **In Fledge, everything is requested:** ADRs, plans, this file, the README, `lib/`, `sig/`, `exe/`, `tasks/`, `test/`, the launcher's C, the workflows. Nothing here is written or wrought. Because no one reviews this work line by line, the gates review it, and Delivery most of all: a built app run on a fresh machine that has never seen Ruby. Never weaken a gate to make requested work pass.
- **The maintainer's words** are in `doc/contributors/decisions.md`, quoted verbatim with the date. That file is the only record of what the maintainer said. Everything else here, ADRs, design documents, plans, and this file included, was written by agents, and agents change it, as long as it stays true to `decisions.md`: design documents, plans, and this file freely, and an accepted ADR only by writing a new one (Questions, below).
- **Generated code** is marked as generated in its header and is never edited by hand; change the generator instead.

Every commit carries a `Provenance: requested` trailer.

## Questions

`doc/contributors/questions.md` holds only two kinds of question:

1. An apparent conflict with, or ambiguity in, `doc/contributors/decisions.md`.
2. Direction only the maintainer can give: product scope (what Fledge is for, and what it is not), licensing and commercial terms, money, and external accounts (Apple, Microsoft, certificate authorities, package registries, a second host for release files). An agent never opens an account, even a free one: when one is wanted, ask the maintainer, with suggestions (decisions, 2026-11-02 and 2026-11-04).

Everything agents invented is the agents' to decide: design-document, ADR, and plan content, CLI details, `fledge.yml` keys, the help header, error messages, internal layouts, and names inside the runtime. Decide it by prior art and industry standards (Design precedence, above). Record the rationale and citations in the design document that specifies it, and write an ADR only when the choice passes the `adr` skill's test: architecturally significant, between real options, one decision. Change a design document freely when a better reason arrives. Do not rewrite an accepted ADR: write a new one, and delete the old one once the new one fully supersedes it, rewriting its citations in the same change. Typo and link fixes are fine. Never ask the maintainer to second-guess an agent's invention; ask only where the maintainer's words leave something open.

A question names its context, the default the work proceeds on, and how to reverse that default. Write it so the maintainer can answer it from the question alone: say what is being asked in plain words, quote the maintainer's own earlier words where they bear on it, and never send the reader to an ADR, a plan, or another file to understand it. Do not wait for an answer: build on the default. When the maintainer answers, add the answer verbatim to `decisions.md` if it is a decision, apply it, and remove the question.

## Licensing

Fledge is MIT, copyright setdef (decisions, 2026-11-07); released tags through `v0.7.0` keep the AGPL-3.0-or-later they were released under. Every line must be clearly Fledge's or clearly attributed, so that Fledge's notice covers only setdef's work and every other author keeps theirs.

- **Derived code and prose get SPDX snippets**, as Tokra does. Anything adapted from elsewhere (Ruby's `main.c`, `ruby.c`, or `win32/win32.c`; RubyGems; RubyInstaller; rv-ruby; Lota; Tokra; a spike) sits between `SPDX-SnippetBegin` and `SPDX-SnippetEnd`, with the source's `SPDX-License-Identifier`, an `SPDX-SnippetCopyrightText` naming the source's authors, and an `SPDX-SnippetComment` naming the source file and the commit or tag it came from. Do this for the maintainer's own projects too: their license or ownership may differ from Fledge's. Add the source's license text to `LICENSES/`; `reuse lint` in the gate checks both.
- **Fledge's runtime carries no copyleft obligation beyond keeping notices** (decision 8). Fledge's own code in it is MIT, which asks only for its notice, and each app's `notices/NOTICES.txt` carries that notice. Fledge never asks an app developer for their app's source or object files. Every third-party component in a runtime (a library, a DLL, a gem, a data file) is one of:
  - under a permissive license such as MIT, BSD, Apache-2.0, Zlib, or Ruby's;
  - an LGPL library shipped as a separate shared library a person can replace, with its source published beside the runtime;
  - an LGPL library linked into another component that is not Fledge's, with both sources published beside the runtime (libfuse in AppImage's runtime, which only installers carry; ADR 049);
  - under a license that asks only that its source be published (CPL-1.0, NSIS's LZMA module), with its source published beside the runtime.
- **These are bugs to remove:** GPL or AGPL third-party code in a runtime, and LGPL code linked into Fledge's launcher or into any binary whose source Fledge does not publish.
- **This policy applies to Fledge's runtimes only.** The gems an app depends on are the app developer's choice and responsibility, licenses and all (2026-10-28; ADR 007). `fledge build` never refuses, warns about, or annotates a gem for its license, for what its binaries compile in, or for declaring no license. It refuses a gem only when it would not run where the app goes: no build for the target, a checksum or pin that does not match, a Ruby it does not support, or a library its compiled files need that nothing provides.
- **Before a component lands in `runtime/sources.yml`,** check its license and record the component, its license, and its notice in `runtime/licenses.yml`. Every runtime build runs the license audit against that file and refuses to archive a runtime with anything it does not account for (ADR 004).
- **`doc/licensing.md` is generated** from the runtimes. When CI says it is stale, regenerate it with `bundle exec rake "licensing[DIR]"`, and change its generator, `tasks/licensing_page.rb`, never the page.

## Committing

- Commit on `trunk` in coherent steps, each after the gate passes, with the plan, ADR, or question each step produced.
- Pushing `trunk` to `origin` (github.com/setdef/Fledge) is allowed once the gate passes; push when a step is done, and never wait for CI to push. A push never cancels a CI run in progress on `trunk` (ADR 071): `fast.yml` judges each push in minutes, and `ci.yml`'s full run covers every commit pushed since the run before it started, so a red full run means one commit of that batch broke it, and `fast.yml`'s verdicts on each push narrow which. Only a release is different: push the release commit and the pin commit each alone, and nothing else between them, because the pin commit's parent must be the release commit, whose run built the runtimes it pins (ADR 014; `doc/contributors/design/releases.md`, "Runs, batches, and the release commit").
- Never force-push, unless the maintainer authorizes it, and then only for commits not yet tagged or released. Never push or tag in any other repository, or to another agent's branch.
- Conventional Commits, plain text, wrapped at 72. The body explains why this approach over alternatives, in prose (no lists, no markdown, no file inventories). Types: `lib`/`sig`/`exe`/launcher feat/fix/refactor/perf; `bin`/`tasks`/CI chore; `examples/` and `doc/` docs; `test/` test. End with the `Provenance: requested` trailer, then the AI footer shown by `git log -n1`.

## Releasing

Before 1.0, agents may push `trunk`, create and push tags (`vX.Y.Z`), and create GitHub Releases (decision 6). Versions are ordinary 0.MINOR.PATCH from 0.1.0 (decisions, 2026-11-02); 1.0 waits until at least some of the unproven things are proven. A release is a git tag and a GitHub Release at https://github.com/setdef/Fledge that carries the prebuilt runtimes as assets, with each runtime's SBOM, NOTICES, and LGPL source bundle beside it. `.github/workflows/release.yml` publishes one when a tag is pushed, once it finds that CI passed on the tagged commit on `trunk` (it does not run CI again), and `installed.yml` then installs Fledge from the tag and delivers hello with the published runtimes.

- Agents cut 0.x releases as work accumulates, so that the newest 0.x release has what 1.0.0 will (decisions, 2026-11-08).
- `doc/contributors/account-tests.md` lists every test blocked on the maintainer's developer accounts; update it in the same commit as any change that adds, proves, or removes one (decisions, 2026-11-08).
- Tag only a commit whose CI is green on every job. A pin commit, which changes only `lib/fledge/SHA256SUMS`, runs a short CI on push: the gate, and a check that its pins match the runtimes of its parent's run, with every other job skipped. It counts as green on every job when that short CI passes and its parent's CI passed on every job with none skipped (ADR 053; `doc/contributors/design/releases.md`, "A pin commit's short CI"). Never delete a release: each runtime's NOTICES links its LGPL source bundle there.
- A release is two commits and a tag (ADR 014): the release commit, then the pin commit that changes only `lib/fledge/SHA256SUMS`, which is the commit to tag. `release.yml` refuses a tag whose commit changes anything else, or whose pins do not match the runtimes it would publish. Do both commits within 14 days, while CI keeps the runtimes. The steps are in `doc/contributors/handoff.md`, How to release.
- Agents never publish to RubyGems.org: no `gem push`, ever. Publishing there is a human-only activity, now and after Fledge is on RubyGems.org (decisions, 2026-11-02). From 1.0.0 Fledge is also released on RubyGems.org by the maintainer, and every release still has its git tag and GitHub Release (decisions, 2026-11-03 and 2026-11-04); agents prepare the release and the maintainer publishes it. Every release still gets its tag, which the schema's address needs; from 1.0, release branches, backports, and `stable` follow RatatuiRuby's tooling, as `doc/contributors/design/releases.md`, "From 1.0: release branches and a human publishing", describes. This rule binds agents and is not a position of the project, so documents for developers do not say Fledge is never published there. The gemspec's `allowed_push_host` points nowhere, and `rake release` refuses.

## Changelog

Keep a Changelog + SemVer. Only changes people who build apps with Fledge, or run apps built with it, can observe: the CLI, behavior, what a built app contains, breaking changes, deprecations, dependency changes (including the pinned Ruby versions and their sources). Not tests, docs, internal refactors, or tooling. Terse one-line entries under `## [Unreleased]`, which means "since the last tag": a change undone before the next tag removes its entry instead of adding a "Fixed" line. Never edit released sections.

## Definition of done

1. Every item in the plan is done, or explicitly deferred with a reason.
2. Behavior follows the design precedence above; deviations from the prior art are justified and documented.
3. `bundle exec rake` passes from a clean build (`rm -rf tmp`), zero errors, zero warnings.
4. RDoc, RBS, the `exe/fledge` help header, the `fledge.yml` schema, `doc/`, README, and CHANGELOG updated where behavior changed.
5. The work is true to `doc/contributors/decisions.md`, and any conflict or open direction is in `doc/contributors/questions.md`.
6. A commit message is written (and the commit made, per Committing).
