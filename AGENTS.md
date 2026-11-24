<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

This file is binding for every agent that works in this repository. It holds the rules every session needs, and says where the rest is.

## Project

Fledge (the `fledge` gem, https://github.com/setdef/Fledge) ships a Ruby app to people who don't have Ruby. It copies the program a developer already runs, with its project and the gems its `Gemfile.lock` locks, into a relocatable CRuby runtime for the platform it runs on, with a small C launcher that starts the program as `bundle exec` would, and archives the result. Each platform's app is built on a computer of that platform, with that platform's own tools. Framework wrappers (Lota, Tokra, Rooibos) call Fledge; Fledge depends on no wrapper's repository. A developer writes their app in Ruby, with whatever front end their framework uses, on every platform, phones included, and never the native code a platform needs: Fledge supplies every line of C, Objective-C, Swift, Java, Kotlin, or any other language an app needs, in its runtime, launcher, and templates, and no example asks for one.

Pre-1.0, zero external users. Prefer good design over backward compatibility; record every breaking change in CHANGELOG.md.

The repository keeps no running account of the project's state (decisions, 2026-11-21): what changed is in CHANGELOG.md and `git log`, and the rest is where the list below says.

## Where to look

- `README.md`: what Fledge does, for app developers.
- `CONTRIBUTING.md`: how to put a question to the maintainer, setup, the tests, checking a change before and after its push, and reading CI.
- `doc/contributors/decisions.md`: the project's decisions that shape what Fledge is and does, each dated (Provenance, below, says how it is kept).
- The open issues of the milestone "1.0.0 release candidate" at github.com/setdef/Fledge: the work left, each issue written so that an agent can start from it. `doc/contributors/plan/003.md`, the plan of record, holds the stories and the direction behind them.
- `doc/contributors/design/`: how each part works, and why. `architecture.md` is the overview, indexes the few ADRs, and says when one is written and how it changes; `releases.md` says how a release is made, and `license-audit.md` how the license policy is enforced.
- `doc/contributors/documentation_style.md`: how to write prose, RDoc, and the READMEs.

## Design precedence

When two parts of the design pull apart, these decide, in this order. `doc/contributors/design/architecture.md`, "What the design answers to", says each in full, with the prior art it names.

1. **A person who double-clicks or runs the app never meets Ruby,** and no Ruby the person happens to have influences the app. This wins over everything below.
2. **The app's Ruby code runs as it does under `ruby main.rb`, or `bundle exec`** (decisions 9, 10, and 20; ADR 081). Fledge must never surprise an app developer with how Ruby, its globals, built-ins, and standard library behave compared with not using Fledge (decisions, 2026-11-02), so a difference is a bug unless `Parity::JUSTIFIED` says why it is right.
3. **Ruby the language and its conventions,** read in Ruby's source at the pinned version, never guessed.
4. **Prior art and standards,** matched, and cited in the design document that specifies the behavior.
5. **Ruby culture,** whose idioms yield to 1 through 4.

## How to work

- Research before designing: read the part's design document, and the prior art's source or documentation. Never guess at a reference's contents; cite the file and lines you relied on.
- Root-cause every fix. If you cannot explain why a change fixed the symptom, it is not a fix.
- Write tests first. A test must fail if the code it covers is deleted or mutated, and must exercise real collaborators, not stubs that hide missing behavior. The acceptance test for a build is a built app run on a fresh machine with no Ruby.
- Code is a liability (decisions, 2026-10-28): never write a tool that a maintained, pinnable tool or gem provides, and pin every external input by version and, where it is downloaded, by SHA-256 (`architecture.md`, "What the design answers to", says both in full). Build each target on its own operating system with that system's tools, never one platform's app on another (decisions, 2026-10-28; ADR 010). Before adding a platform, first check whether a maintained project already publishes a portable Ruby for it (decisions, 2026-11-22).
- Add no requirement that no decision or story calls for without weighing what it costs, and say what it costs when you propose one.
- Design in the spirit of Kent Beck (small steps), Freeman & Pryce (tests drive interfaces), Sandi Metz (duplication over the wrong abstraction), Rebecca Wirfs-Brock (responsibility-driven roles), Martin Fowler (behavior-preserving refactors), and Matz (programmer happiness).

## Working as an agent

- Proceed through the plan of record without checking in with the maintainer. Decide what is the agents' to decide (Questions, below), record it, and go on. Come back only when truly blocked.
- No change leaves a design document false, or a fact an ADR cites as proof (a test, an example, a path): correct it in the same change. Code that falls short of an ADR on purpose is a defect, which its design document states.
- Work trunk-based, as trunkbaseddevelopment.com describes (decisions, 2026-11-12): small commits pushed straight to `trunk`, no long-lived or sideways branches, never push-and-poll, and a red `trunk` reverted at once. CONTRIBUTING.md, "Before a push" and "After a push", says how.
- Leave existing `spike/*`, `wip/*`, and `experiment/*` branches alone, and delete no branch.
- A commit that fixes an issue ends its body with "Fixes #N". File a defect you find, or work the candidate needs, as an issue in the milestone: a title that states it as a plain sentence, and the evidence you hold (the command, its output, the conditions), not where the fix might be. Agents may comment on, edit, and close the project's issues.
- Post nothing on another project's tracker. A fault that is another project's is an issue here labelled `upstream`, saying whose it is and what Fledge does meanwhile; whether to report it there is the maintainer's (decisions, 2026-11-22, on whose bug a fault is).

## Code and docs

- `Data.define` for value objects (`class Foo < Data.define(...)`), `class` for entities.
- Every Ruby method has an RBS signature in `sig/` mirroring `lib/`, with no `untyped` and no comments. A `Data.define` class declares `self.new`, not `initialize`, which Steep mis-checks there. An exception goes in `rbs_exceptions.rb` only with a justification that nothing else is possible.
- RDoc, never YARD, in `.rb` files only. Write it, and all prose, as `doc/contributors/documentation_style.md` describes, and before you edit `README.md` or `README.rdoc`, read both in full (its "README.md and README.rdoc").
- The help `fledge --help` prints is the comment header in `exe/fledge`, between the `####` and `###` lines: change it with the CLI.
- `lib/fledge/config.schema.json` describes `fledge.yml`: change it with `Fledge::Config`; a test fails when they disagree.
- No file in `lib/` may be rated F by RubyCritic, which itself fails nothing. Read its report after a change; when a file falls toward F, give the responsibility it took on a class of its own.
- Generated files, `doc/licensing.md` among them, say so in their header and are never edited by hand: change the generator.

## Commands

- An agent's shell runs no hook of `mise activate`, so its `ruby` may not be the one `mise.toml` pins, and Bundler then stops with a stack trace: start every command with `mise x --`.
- Run Ruby with `bundle exec ruby`, never `ruby -Ilib:test`. Always `PAGER=cat` for git.
- Before every push, `mise x -- ruby bin/check`, and beside it the one test of the behavior the change alters (`TEST=test/foo_test.rb`). For a change to a runtime, or to the Ruby a parity check compares one with, run `mise x -- ruby bin/check --runtime` on a computer of that platform instead (CONTRIBUTING.md, "Before the push of a runtime change").
- `bundle exec rake test` runs the unit tests, in seconds; `bundle exec rake test:all` adds those in `test/integration/`. A unit test takes milliseconds: one that builds or reads a runtime, runs an app it built, compiles, starts a Ruby or a script, signs, or reaches the network is an integration test (CONTRIBUTING.md, "The tests"). Fast, reliable tests are a maxim (decisions, 2026-11-22): a test slow for its tier, or failing for no fault in the code, is a defect.
- `bundle exec rake` is the gate, which CI runs: every test and every lint, with zero errors and zero warnings.
- Rake tasks use `git ls-files`: stage new or deleted files before they count.

## Provenance

Everything in Fledge is *requested*: an agent built it with little or no review, as against *written* by the maintainer's hand or *wrought* with the maintainer's review of every change (decisions, 2026-11-02, later again). That holds for ADRs, plans, this file, the README, the code, the tests, and the workflows. Because no one reviews this work line by line, the gates review it, and Delivery most of all: a built app run on a fresh machine that has never seen Ruby. Never weaken a gate to make requested work pass. Every commit carries a `Provenance: requested` trailer.

`doc/contributors/decisions.md` holds, dated, only the decisions that shape what Fledge is or does, each stated as the project's rule; corrections, wording changes, and asides go into the document they touch. An answer to a `question` issue is applied and the issue closed, and the documents that apply it state the rule as the project's. Everything else, this file included, was written by agents, who change it as long as it stays true to decisions.md.

The maintainer's conversations with agents are private. Nothing public (a file here, an issue, a comment, a commit message) quotes him, paraphrases him, or says what he said, asked, wanted, suggested, preferred, ruled, or decided, and nothing public carries private details of his setup, his machines, or his accounts, or his informal remarks about other projects, people, or controversies. Work and its reasons are stated as the project's own. A statement of who does what (that a person publishes to RubyGems.org, or opens an account) stays, said without reporting what anyone said. An issue or comment that breaks this is deleted, not edited, since an edit keeps its history.

## Questions

A question is an open issue labelled `question`, assigned to the maintainer, of one of two kinds:

1. An apparent conflict with, or ambiguity in, `doc/contributors/decisions.md`.
2. Direction only he can give: product scope, licensing and commercial terms, money, and external accounts (Apple, Microsoft, certificate authorities, package registries, a second host for release files). An agent never opens an account, even a free one: when one is wanted, ask him, with suggestions (decisions, 2026-11-02 and 2026-11-04).

Everything agents invented is the agents' to decide: design-document, ADR, and plan content, CLI details, `fledge.yml` keys, the help header, error messages, internal layouts, and names inside the runtime. Decide it by the design precedence, record why in the design document that specifies it, and change it when a better reason arrives. Never ask him to second-guess an agent's invention, and ask nothing hypothetical: a question is about something that exists or is about to (decisions, 2026-11-22).

Write one, and act on its answer, as CONTRIBUTING.md, "Ask for what you want", says, and build on its default meanwhile.

## Licensing

Fledge is MIT, copyright setdef (decisions, 2026-11-07); released tags through `v0.7.0` keep the AGPL-3.0-or-later they were released under. Every line is clearly Fledge's or clearly attributed, so that Fledge's notice covers only setdef's work and every other author keeps theirs.

- **Code or prose adapted from elsewhere** (Ruby's sources, RubyGems, RubyInstaller, rv-ruby, Lota, Tokra, a spike, the maintainer's own projects too) sits between `SPDX-SnippetBegin` and `SPDX-SnippetEnd`, with the source's `SPDX-License-Identifier`, an `SPDX-SnippetCopyrightText` naming its authors, and an `SPDX-SnippetComment` naming the source file and its commit or tag. Add the source's license text to `LICENSES/`; `reuse lint` checks both.
- **Fledge's runtime carries no copyleft obligation beyond keeping notices** (decision 8), and Fledge never asks an app developer for their app's source or object files. GPL or AGPL third-party code in a runtime, and LGPL code linked into Fledge's launcher or into any binary whose source Fledge does not publish, are bugs to remove. `doc/contributors/design/license-audit.md` says what a runtime may hold, and how its build refuses the rest; a component's license and notice are recorded in `runtime/licenses.yml` before it lands in `runtime/sources.yml`.
- **This policy applies to Fledge's runtimes only.** The gems an app depends on are the app developer's choice and responsibility, licenses and all (decisions, 2026-10-28): `fledge build` judges no gem by its license, and refuses one only when it would not run where the app goes (`doc/contributors/design/gems.md`, "Checks that are not about licenses").

## Committing

- Commit each step with the plan or question it produced, and push it to `trunk` on `origin` (github.com/setdef/Fledge).
- Never force-push, unless the maintainer authorizes it, and then only for commits not yet tagged or released. Never push or tag in any other repository, or to another agent's branch.
- Conventional Commits, plain text, wrapped at 72. The body explains, in prose, why this approach over the alternatives: no lists, no markdown, no file inventories. Types: `lib`/`sig`/`exe`/launcher feat/fix/refactor/perf; `bin`/`tasks`/CI chore; `examples/` and `doc/` docs; `test/` test. End with the `Provenance: requested` trailer, then the AI footer `git log -n1` shows, with no blank line between them.

## Releasing

Before 1.0, agents may push `trunk`, create and push tags (`vX.Y.Z`), and create GitHub Releases (decision 6). Versions are 0.MINOR.PATCH from 0.1.0 (decisions, 2026-11-02), and agents cut 0.x releases as work accumulates, so that the newest has what 1.0.0 will (decisions, 2026-11-08). A release is cut only by `cut.yml`, on a commit whose CI passed on every job, and is never deleted, since each runtime's NOTICES links its LGPL source bundle there: `doc/contributors/design/releases.md`, "How a release is made", says how, and what a release holds.

- Keep `doc/contributors/account-tests.md`, every test blocked on the project's developer accounts, current in the same commit as any change that adds, proves, or removes one (decisions, 2026-11-08).
- Agents never publish to RubyGems.org: no `gem push`, ever. Publishing there is a human-only activity, now and after Fledge is on RubyGems.org (decisions, 2026-11-02). A deterministic process the maintainer has decided to trust with it counts as a person's act: a workflow that RubyGems.org has been set to trust, which no agent sets up (decisions, 2026-11-22). From 1.0.0 the maintainer also releases Fledge there, and every release keeps its git tag and GitHub Release (decisions, 2026-11-03 and 2026-11-04); agents prepare the release and the maintainer publishes it. The rule binds agents and is not a position of the project, so documents for developers do not say Fledge is never published there. The gemspec's `allowed_push_host` points nowhere, and `rake release` refuses.

## Changelog

Keep a Changelog and SemVer, in terse one-line entries under `## [Unreleased]`, which means "since the last tag". Record only what people who build apps with Fledge, or run them, can observe: the CLI, behavior, what a built app contains, breaking changes, deprecations, and dependency changes, the pinned Rubies and their sources among them; not tests, docs, internal refactors, or tooling. A change undone before the next tag removes its entry instead of adding a "Fixed" line. Never edit a released section.

## Definition of done

1. Every item of the story is done, or deferred with a reason.
2. Behavior follows the design precedence; a departure from prior art is justified in its design document.
3. The gate passes in `trunk`'s CI on the story's last commit, with zero errors and zero warnings.
4. RDoc, RBS, the help header, the `fledge.yml` schema, `doc/`, the READMEs, and CHANGELOG.md are true to the new behavior.
5. The work is true to `doc/contributors/decisions.md`, and any conflict or open direction is an open `question` issue.
6. It is committed and pushed, per Committing.
