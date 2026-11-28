<!-- ONLY HUMANS MAY EDIT THIS FILE! -->
<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Working on Fledge

These are the working rules for everyone who changes this repository: people, and the AI agents they run. They are the project's shared rules, so they apply to every contributor, humans and AI agents alike.

## The Tao of Fledge

Fledge is a runtime in which an app's Ruby behaves exactly as it does under `ruby main.rb` (or `bundle exec`), on every desktop and on every phone, and a CLI tool to package that app. It gives the app no helpers, no bridges, no APIs of its own. Fledge's purpose is to help Ruby compete with Go for easy-to-install CLI tools, with Lua for cross-platform video games, with Dart for phone apps, and with C# for desktop development. When an app's pure Ruby cannot do something on some platform, the only fix is to make Fledge's Ruby a truer Ruby there; never to add something of Fledge's for the app to call. Anything an app needs beyond Ruby (a bridge to Objective-C or Java, a widget toolkit, a game framework) is the app's own Ruby or a gem's, never Fledge's.

- Phone examples are the proof: Basket drives UIKit and Android's views by each platform's interface guidelines in pure Ruby (its own code, Ruby's standard library and bundled gems, Fiddle), with no bridge gem that has a native extension; a pure-Ruby gem is allowed. Getting there is meant to be hard: it is what drives Fledge's foundational decisions (main thread, closures under code signing, reaching system libraries). `Fledge::ObjC`, `Fledge::JNI`, `RubyProxy`, and every other affordance are the shortcut this rules out.

## What the project is

Fledge copies a Ruby program, its project, and the gems its `Gemfile.lock` locks into a relocatable CRuby runtime for the platform it runs on, with a small C launcher that starts the program as `bundle exec` would, and packages the result as an app.

Write its name as Fledge; the gem and the command are `fledge`, and the Ruby module `Fledge`.

## Committing to the trunk

The project practices trunk-based development.

- **Run the tests** with `mise x -- ruby bin/check`.
- **Check code or tests that behave differently on Windows, on Windows.** This covers anything that reads `File::ALT_SEPARATOR` or `Gem.win_platform?`, and anything that depends on paths, line endings, `fork`, or signals.
- **Check a change to `.github/workflows/*.yml`** by loading the file with `YAML.safe_load_file` and running each changed `run:` string exactly as YAML parsed it.
- **When the push is refused because `trunk` moved,** read the diff, rebase, run the gate again if risky, and push again. Read the diff every time, even when the incoming commit messages look unrelated: two changes can rebase cleanly and still break each other.
- **After you push, wait for nothing.** Don't watch a CI/Proof run or poll for its result. Check work before the push, not after it.
- **Keep every push releasable.** When a goal takes several commits, hide the unfinished code behind a feature flag or build it by branch by abstraction, and land it in slices.
- **Every agent pushes the commits it wrote immediately.** Nobody collects other agents' commits to land them, nobody sets a landing order or asks others to stop pushing, and nobody keeps working with gate-passing unpushed commits.
- **Fix or quarantine a flaky test right away,** recording the reason, instead of rerunning it until it passes. Never delete or disable a test to make the build faster.
- **Review on origin.** Review never blocks a push that passes the gate, because follow-up commits and reverts handle feedback.

## Spikes

A spike, prototype, or probe is throwaway code. It never reaches `trunk`, and nobody pushes it anywhere else either, except a probe that needs CI's runners, which may go on a throwaway branch if needed. When it's done and you've [written things down](#writing-things-down) delete the spike. Write production code afresh after the decision, and never grow it from a spike.

## Commit messages

Write every commit message in the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) format: `<type>(<scope>): <description>`, or `<type>: <description>` with no scope.

- The type is one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, or `revert`, in lowercase.
- The scope is optional. It is the part of the code the change affects, in lowercase.
- The description is a short summary in the imperative mood ("add", not "added" or "adds"), with no period at the end.
- A body, after a blank line, explains why this implementation was chosen over others. It never re-states the diff or explains anything obvious from reading the patch.
- A breaking change has a `BREAKING CHANGE: <description>` footer.
- An agent commit has a `Co-authored-by: <model-and-version>` footer.

For example: `fix(runtime): ask only a live pipe how much output is pending`, or `docs: describe the runtime's pins`.

## Writing code

- **Get each fact from its source.** Run the tool, read the current documentation or source, or read a run's result. This matters most for facts that depend on a version, such as a gem's API or how Ruby behaves in a given version, because memory about a dependency goes stale, especially for projects that change often. Never pass on an AI agent's or a tool's claim as fact without checking it, and say which facts you checked and which you didn't.
- **Reuse before you build.** The project carries as little code as it can. Before you write a parser, protocol, server, format reader, cryptographic primitive, or anything else of that kind, look for reliable code that already exists: the Ruby standard library first, then gems that are maintained, documented, and tested. Code written for this repository in place of a library needs the same written reason that a new dependency does.
- **Code is a liability.** The more code the project carries, the more can go wrong and the harder it is to maintain.
- **Improve software design** according to the Boy Scout Rule, with refactorings in separate commits before implementation. Make the change easy (warning: this may be hard), then make the easy change.
- **TDD tests every change in behavior.** Confirm that each new test fails without the change: a test that passes either way proves nothing.
- **Update the user documentation** in the same commit as a change to anything users see. Watch your prose style, and use best practices for developer docs.
- **Write the doc comment** for every public class, module, constant, and method in the matching `.rbs` declaration in `sig/`. A comment directly above a `def`, `class`, or `module` in `lib/` would be RDoc documentation, which doesn't go in `.rb` files. Don't leave commented-out code, history notes, or decorative divider comments in the source.
- **Comment why, not what.** Rename a variable or extract a method instead of explaining unclear code. Write a comment for a reason the code can't show, such as a constraint from outside the project or the choice of an algorithm.

## Writing things down

| Axis | As it is | As it will be |
| - | - | - |
| Requirements: what the software does for its users | User documentation† | Issues |
| Contract: what a caller can rely on | Doc comments; the changelog, for changes over time | Issues |
| Architecture: the few decisions the structure rests on | Accepted ADRs | Proposed ADRs |
| Design: how each part works, and why | Design documents | Nowhere |
| Behavior: what the code does | Tests | Nowhere |
| Facts that constrain the design | The design document or ADR they constrain; until that exists, the issue whose work they constrain | Nowhere |

- **Decide a design at the last responsible moment,** while building it, with the facts in hand, then record it as it is. Never write a design, or a behavior, ahead of the code, in an issue or anywhere else.
- **A design document explains a part to the people who change it:** its concepts, how its pieces fit, why it is shaped this way, its traps, and what it deliberately doesn't do. It doesn't restate the code: no fields, option types, step-by-step restatements of the code, or private call graphs.
- **Change a design document when a design decision changes,** never because behavior did. The two vary independently.
- **A doc comment describes the contract from the caller's side,** never how the code does the work inside.
- **Check a fact at its source before anything rests on it,** on the platform it's about. A decision that rests on an unchecked fact waits.
- **Record a fact found before its design exists as a fact, not a decision:** what was spiked or checked, how, on which platform and version, and the result. It waits in the issue whose work it constrains. When the design or architecture is decided, the relevant facts go in that design document or ADR.
- **Issues may represent proposed or accepted** requirements or contracts, and an issue that doesn't specify which can't be assumed to have already been accepted or denied.
- **`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).** It lists only what changes for the people who use the project: new commands, flags, and public APIs; behavior they can observe; deprecations; removals; and breaking changes. Write each entry for them, never as a restatement of a diff or a commit message. Tests, documentation, refactorings, examples, tooling, CI, and style changes stay out. New entries go under Unreleased, which covers the time since the last tag, so a commit that undoes an earlier unreleased change removes its entry. Once a release's section is dated, never edit it.
- † **In a project being built under README-Driven Development,** the user documentation is written ahead of the code, as its requirements. Everywhere else, it describes only what the software does today.

## Security

Fledge copies other people's programs, projects, and gems into apps that run on their users' computers, so treat every path, setting, and line of output that comes from them as untrusted input.

- Start a subprocess with an array of arguments, never a single string a shell would parse.
- Build file paths from parts with `File.join` or `Pathname`, and check that a path built from outside input stays inside the directory you meant it for.
- Never hardcode a secret, such as an API key. Take a secret from a file or standard input, never from a flag or an environment variable: the system shows every process's arguments to other users in its process listing, and every child process inherits the environment. Never print a secret.
- Before every network request, have the program say on standard error what it is about to do, and give the request a time limit, so that no command waits on the network in silence or forever.
- A built app runs with the rights of the person who opens it. Never widen what it can reach.
- Never call `Marshal.load` or `YAML.unsafe_load` on data from outside the process.
- Commits, issues, comments, docs, and code contain only what anyone could find in public sources. Never put in them your machine's names, paths, or hardware, or anything said in a private conversation, and never quote a person from one. An ADR lists its deciders by role, with links to the public issues.

## Quality gates

`bundle exec rake` runs the quality gates: the unit and integration tests, test coverage, RuboCop, Steep and the RBS checks, RubyCritic, RDoc coverage, `docs:placement` (which fails on a doc comment in a `.rb` file), `reuse lint`, actionlint and shellcheck, clang-format, and the check of the packaged gem. Every change has to pass all of them, with zero errors and zero warnings. Their thresholds only ever go up. When a change fails a gate, fix the change; never lower a threshold, turn off a check, or exclude code to get it through.

Coverage is 100% for each file, on every system CI tests. A test skipped on one system can drop that system's branch coverage below 100% and turn its job red, even though every test passes. Never skip a test on one system to make it pass. Pass the system-dependent value in, such as a path separator or a platform flag, so the test runs everywhere.

When a gate (a RubyCritic score, a Reek smell, a RuboCop length limit) pushes the design, it's actually pushing you to remember OOA&D & OOP best practices. They properly flag bad code, but their suggestions are naive. Don't game them or comply naively; take responsibility for the object design improving over time.

### What the maintainer decides

Ask the maintainer before you change any of these:

- product scope
- licensing
- significant changes to UX/DX (commands, flags, environment variables, file formats, etc).

## Copyright and licenses

The project follows the [REUSE Specification](https://reuse.software/spec-3.3/). SPDX headers in files are only for content under a copyleft or share-alike license. Ported code goes between snippet comments, as its license requires. Examples in documentation also use snippet comments, MIT-0. `REUSE.toml` contains the license information for content under a permissive or public-domain license. The project's code and configuration are MIT and its documentation CC-BY-4.0, both permissive, so they have no SPDX headers; `REUSE.toml` covers them.

A file under a copyleft or share-alike license must not be copied from elsewhere without permission from the maintainer. An approved copyleft or share-alike file, or a file copied under a permissive or public-domain license, has that license in its SPDX header, and the license's text goes in `LICENSES/`. Run `reuse lint` before you push when copying or porting code.

Code ported from another project (an algorithm translated into Ruby, a table, a regex, etc.), as opposed to code only inspired by it, goes between `# SPDX-SnippetBegin` and `# SPDX-SnippetEnd` comments in its file. Inside them, give the upstream license as `SPDX-License-Identifier`, the upstream copyright as `SPDX-SnippetCopyrightText`, and an `SPDX-SnippetComment` that gives the upstream project's name and file and says what the port changed. `reuse lint` must still pass.
