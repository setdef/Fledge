<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
- `doc/contributors/adr/`: why each part is the way it is. ADR 001 is the overview.
- `doc/contributors/questions.md`: what only the maintainer can answer.

## Design precedence

1. **A person who double-clicks or runs the app never meets Ruby.** No install step, no Ruby on `PATH`, no error that names a gem, no influence from a Ruby the person happens to have (`RUBYLIB`, `RUBYOPT`, `GEM_HOME`, and the rest are hidden from Ruby's boot, and the app's gems are the runtime's). When anything below conflicts with this, this wins.
2. **The app's Ruby code runs as it does under `ruby main.rb`, or `bundle exec`.** Same requires, same globals, same `ENV`, same standard library, bundled gems, and locked gems (decisions 9, 10, and 20; ADR 003 and ADR 005). The parity check proves it on every platform; a difference is a bug unless `Parity::JUSTIFIED` says why it is right.
3. **Ruby the language and its conventions.** RubyGems platform names for targets, CRuby's own `main.c` for how the launcher starts the interpreter, Ruby's layout for the standard library. Read the source at the pinned Ruby version; do not guess.
4. **Prior art and standards.** GNU's and POSIX's command-line conventions, sysexits.h, LÖVE's fused games, the Tauri bundler, PyInstaller and Briefcase, and python-build-standalone. When Fledge needs a behavior these already settled, match them and cite them in an ADR.
5. **Ruby culture.** Idioms yield to 1 through 4.

## How to work

- Research before designing: read the relevant ADR and the prior art's source or documentation first. Never guess at a reference's contents; cite the file and lines you relied on.
- Root-cause every fix. If you cannot explain why a change fixed the symptom, it is not a fix.
- Write tests first. A test must fail if the code it covers is deleted or mutated, and must exercise real collaborators, not stubs that hide missing behavior. Test the CLI through real streams (injected `StringIO`) and as a subprocess. The acceptance test for a build is a built app run on a fresh machine with no Ruby.
- Code is a liability (decisions, 2026-10-28). Never write a file format, archive, image codec, signer, or other tool that a maintained, pinnable tool or gem already provides; use the tool, built or run on the platform it belongs to. Write code only for what no such tool does, and say in the ADR which tools were considered and why none fit.
- Build each target on its own operating system, with that system's tools, as Tauri, Electron's tooling, and Briefcase do; Fledge does not build one platform's app on another (decisions, 2026-10-28).
- Pin every external input (Ruby builds, actions, tools, gems) by version and, where it is downloaded, by SHA-256. Updates arrive on purpose.
- Add no requirement the maintainer did not ask for without weighing what it costs, and say what it costs when you propose one.
- Design in the spirit of Kent Beck (small steps, Implementation Patterns), Freeman & Pryce (tests drive interfaces), Sandi Metz (duplication over the wrong abstraction), Rebecca Wirfs-Brock (responsibility-driven roles), Martin Fowler (refactor in behavior-preserving steps), and Matz (programmer happiness). Write prose as `doc/contributors/documentation_style.md` describes.

## Working as an agent

- Proceed through the plan of record without checking in with the maintainer. Decide what is the agents' to decide (Questions, below), record it, and go on to the next story. Come back only when truly blocked.
- A session that orchestrates others delegates each story to a subagent and verifies what the subagent reports before passing it on: its commits with `git log` and `git show`, its CI runs and releases with `gh run view` and `gh release view`. A claim nobody checked is not reported as done.
- Give a subagent the context the work needs, the rules that bind it, and nothing the maintainer did not ask for.
- A subagent that works in parallel uses its own worktree and branch, and does not push `trunk`. An experiment of CI changes goes on an `experiment/*` branch that runs only the jobs in question. Leave existing `spike/*`, `wip/*`, and `experiment/*` branches alone, and do not delete branches.
- `doc/contributors/decisions.md` holds only the maintainer's meaningful decisions, the ones that shape what Fledge is or does. Corrections, wording changes, and asides go into the document they touch.
- Messages to another project's agent session are brief: what is needed, from which file or commit, and nothing else.

## Ruby, RBS, and docs

- `Data.define` for value objects (`class Foo < Data.define(...)`), `class` for entities.
- Every Ruby method has an RBS signature in `sig/` mirroring `lib/`. No `untyped`, no comments in `.rbs`. For `Data.define` classes, declare `self.new` instead of `initialize` (Steep mis-checks `initialize` there); plain classes declare `initialize` as usual.
- RDoc (never YARD) in `.rb` files only. Wrap SPDX headers in `#--` / `#++`, and wrap examples in `MIT-0` SPDX snippets.
- The help `fledge --help` prints is the comment header in `exe/fledge`, between the `####` and `###` lines. Change the CLI and that header together.
- `lib/fledge/config.schema.json` describes `fledge.yml`. Change `Fledge::Config` and the schema together; a test fails when they disagree.
- Architectural decisions get an ADR; plans live in `doc/contributors/plan/`.

## Commands

- Run Ruby with `bundle exec ruby`. Run tests with `bundle exec rake test`. Never `ruby -Ilib:test`.
- `bundle exec rake` is the gate: RuboCop and REUSE fixes, tests, RuboCop, RubyCritic, RDoc coverage, REUSE, actionlint and shellcheck, RBS checks (no `untyped`, `rbs validate`, signature parity), Steep, and the package check. It must pass with zero errors and zero warnings. Run `bundle exec rake rubocop:autocorrect_all` first to save time.
- RubyCritic reports a score and a rating for each file and fails nothing. Read its report after a change: no file in `lib/` may be rated F, and when one falls toward it, find the responsibility it took on and give that a class of its own.
- Approved exceptions live in `rbs_exceptions.rb`; adding one needs a justification that it is impossible otherwise.
- Rake tasks use `git ls-files`: stage new or deleted files before they count.
- `bundle exec rake parity` compares an app built from this computer's runtime with `ruby main.rb` on the Ruby that runtime came from, and a gem-shaped one with `bundle exec`. Run it after `bundle exec rake runtime`. CI runs it on every platform.
- Run anything that can take focus or the pointer on this computer, such as a phone simulator, under the desktop input lock: `bundle exec desktop_input_lock hold -- COMMAND`. It is silent, and the lock is held only while COMMAND runs. CI needs no lock.
- Always `PAGER=cat` for git.

## Provenance

The maintainer uses three words for how code comes to exist (decisions, 2026-11-02, later again). *Written* means the maintainer typed it by hand, with nothing generated. *Wrought* means an AI agent generated it while the maintainer iterated with it, and the maintainer reviewed every change before committing it, so the maintainer takes responsibility for every diff. *Requested* means an agent built it with little or no review from the maintainer, in the style of a "dark factory."

- **In Fledge, everything is requested:** ADRs, plans, this file, the README, `lib/`, `sig/`, `exe/`, `tasks/`, `test/`, the launcher's C, the workflows. Nothing here is written or wrought. Because no one reviews this work line by line, the gates review it, and Delivery most of all: a built app run on a fresh machine that has never seen Ruby. Never weaken a gate to make requested work pass.
- **The maintainer's words** are in `doc/contributors/decisions.md`, quoted verbatim with the date. That file is the only record of what the maintainer said. Everything else here, ADRs, plans, and this file included, was written by agents, and agents change it freely, as long as it stays true to `decisions.md`.
- **Generated code** is marked as generated in its header and is never edited by hand; change the generator instead.

Every commit carries a `Provenance: requested` trailer.

## Questions

`doc/contributors/questions.md` holds only two kinds of question:

1. An apparent conflict with, or ambiguity in, `doc/contributors/decisions.md`.
2. Direction only the maintainer can give: product scope (what Fledge is for, and what it is not), licensing and commercial terms, money, and external accounts (Apple, Microsoft, certificate authorities, package registries).

Everything agents invented is the agents' to decide: ADR and plan content, CLI details, `fledge.yml` keys, the help header, error messages, internal layouts, and names inside the runtime. Decide it by prior art and industry standards (Design precedence, above), record the rationale and citations in an ADR, and change it freely when a better reason arrives. Never ask the maintainer to second-guess an agent's invention; ask only where the maintainer's words leave something open.

A question names its context, the default the work proceeds on, and how to reverse that default. Do not wait for an answer: build on the default. When the maintainer answers, add the answer verbatim to `decisions.md` if it is a decision, apply it, and remove the question.

## Licensing

Fledge is AGPL-3.0-or-later (decision 1), and setdef may offer it under a commercial license too, so every line must be clearly Fledge's or clearly attributed.

- **Derived code and prose get SPDX snippets**, as Tokra does. Anything adapted from elsewhere (Ruby's `main.c`, `ruby.c`, or `win32/win32.c`; RubyGems; RubyInstaller; rv-ruby; Lota; Tokra; a spike) sits between `SPDX-SnippetBegin` and `SPDX-SnippetEnd`, with the source's `SPDX-License-Identifier`, an `SPDX-SnippetCopyrightText` naming the source's authors, and an `SPDX-SnippetComment` naming the source file and the commit or tag it came from. Do this for the maintainer's own projects too: their license or ownership may differ from Fledge's. Add the source's license text to `LICENSES/`; `reuse lint` in the gate checks both.
- **Fledge's runtime carries no copyleft obligation beyond keeping notices** (decision 8), except Fledge's own code, which is AGPL-3.0-or-later and commercially licensable. A developer who buys a commercial license must be able to ship an app with no copyleft obligation from Fledge at all. Fledge never asks an app developer for their app's source or object files. Every third-party component in a runtime (a library, a DLL, a gem, a data file) is one of:
  - under a permissive license such as MIT, BSD, Apache-2.0, Zlib, or Ruby's;
  - an LGPL library shipped as a separate shared library a person can replace, with its source published beside the runtime;
  - an LGPL library linked into another component that is not Fledge's, with both sources published beside the runtime (libfuse in AppImage's runtime, which only installers carry; ADR 010);
  - under a license that asks only that its source be published (CPL-1.0, NSIS's LZMA module), with its source published beside the runtime.
- **These are bugs to remove:** GPL or AGPL third-party code in a runtime, and LGPL code linked into Fledge's launcher or into any binary whose source Fledge does not publish.
- **This policy applies to Fledge's runtimes only.** The gems an app depends on are the app developer's choice and responsibility, licenses and all (2026-10-28; ADR 007). `fledge build` never refuses, warns about, or annotates a gem for its license, for what its binaries compile in, or for declaring no license. It refuses a gem only when it would not run where the app goes: no build for the target, a checksum or pin that does not match, a Ruby it does not support, or a library its compiled files need that nothing provides.
- **Before a component lands in `runtime/sources.yml`,** check its license and record the component, its license, and its notice in `runtime/licenses.yml`. Every runtime build runs the license audit against that file and refuses to archive a runtime with anything it does not account for (ADR 004).
- **`doc/licensing.md` is generated** from the runtimes. When CI says it is stale, regenerate it with `bundle exec rake "licensing[DIR]"`, and change its generator, `tasks/licensing_page.rb`, never the page.

## Committing

- Commit on `trunk` in coherent steps, each after the gate passes, with the plan, ADR, or question each step produced.
- Pushing `trunk` to `origin` (github.com/setdef/Fledge) is allowed once the gate passes. A push cancels the CI run in progress on `trunk`, and the newer run covers what the older one did, so push when a step is done. Only a release is different: do not push between a release's commit and the end of its CI run, because the pin commit needs that run's runtimes (ADR 014).
- Never force-push, unless the maintainer authorizes it, and then only for commits not yet tagged or released. Never push or tag in any other repository, or to another agent's branch.
- Conventional Commits, plain text, wrapped at 72. The body explains why this approach over alternatives, in prose (no lists, no markdown, no file inventories). Types: `lib`/`sig`/`exe`/launcher feat/fix/refactor/perf; `bin`/`tasks`/CI chore; `examples/` and `doc/` docs; `test/` test. End with the `Provenance: requested` trailer, then the AI footer shown by `git log -n1`.

## Releasing

Before 1.0, agents may push `trunk`, create and push tags (`vX.Y.Z`), and create GitHub Releases (decision 6). Versions are ordinary 0.MINOR.PATCH from 0.1.0 (decisions, 2026-11-02); 1.0 waits until at least some of the unproven things are proven. A release is a git tag and a GitHub Release at https://github.com/setdef/Fledge that carries the prebuilt runtimes as assets, with each runtime's SBOM, NOTICES, and LGPL source bundle beside it. `.github/workflows/release.yml` publishes one when a tag is pushed, once it finds that CI passed on the tagged commit on `trunk` (it does not run CI again), and `installed.yml` then installs Fledge from the tag and delivers hello with the published runtimes.

- Tag only a commit whose CI is green on every job. Never delete a release: each runtime's NOTICES links its LGPL source bundle there.
- A release is two commits and a tag (ADR 014): the release commit, then the pin commit that changes only `lib/fledge/SHA256SUMS`, which is the commit to tag. `release.yml` refuses a tag whose commit changes anything else, or whose pins do not match the runtimes it would publish. Do both commits within 14 days, while CI keeps the runtimes. The steps are in `doc/contributors/handoff.md`, How to release.
- Agents never publish to RubyGems.org: no `gem push`, ever. Publishing there is a human-only activity, now and after Fledge is on RubyGems.org (decisions, 2026-11-02). This rule binds agents and is not a position of the project, so documents for developers do not say Fledge is never published there. The gemspec's `allowed_push_host` points nowhere, and `rake release` refuses.

## Changelog

Keep a Changelog + SemVer. Only changes people who build apps with Fledge, or run apps built with it, can observe: the CLI, behavior, what a built app contains, breaking changes, deprecations, dependency changes (including the pinned Ruby versions and their sources). Not tests, docs, internal refactors, or tooling. Terse one-line entries under `## [Unreleased]`, which means "since the last tag": a change undone before the next tag removes its entry instead of adding a "Fixed" line. Never edit released sections.

## Definition of done

1. Every item in the plan is done, or explicitly deferred with a reason.
2. Behavior follows the design precedence above; deviations from the prior art are justified and documented.
3. `bundle exec rake` passes from a clean build (`rm -rf tmp`), zero errors, zero warnings.
4. RDoc, RBS, the `exe/fledge` help header, the `fledge.yml` schema, `doc/`, README, and CHANGELOG updated where behavior changed.
5. The work is true to `doc/contributors/decisions.md`, and any conflict or open direction is in `doc/contributors/questions.md`.
6. A commit message is written (and the commit made, per Committing).
