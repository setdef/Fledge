<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

Decisions that belong to the maintainer (AGENTS.md, Provenance) wait here. None of them blocks work: each names the default the work proceeds on, chosen to be easy to reverse, and how to reverse it. When a question is answered, record the answer in an ADR or a plan, and remove it from this list.

## 1. What license covers the files Fledge copies into the apps people ship?

**Context.** Fledge's code is AGPL-3.0-or-later, like the maintainer's other projects. Most of Fledge only runs on the developer's machine, so its license binds Fledge and not the apps it builds. But some of Fledge travels inside every app: the C launcher, and any Ruby, scripts, or templates the runtime adds. If those are AGPL-3.0-or-later, every app built with Fledge arguably combines with AGPL code and carries its obligations, including apps whose authors chose a permissive or proprietary license. A game made with Lota, a desktop app made with Tokra, and a terminal tool made with Rooibos would all inherit the question. Prior art leans permissive here: LÖVE, which a fused game ships whole, is Zlib; PyInstaller's bootloader is GPL with an exception that lets it ship inside apps of any license; Ruby's own license and BSD-2-Clause cover the interpreter the runtime ships.

**Default.** Everything in this repository stays AGPL-3.0-or-later, the launcher included, until this is answered. No launcher code exists yet, so nothing has shipped under it.

**Options.** License the runtime files (the launcher and anything else copied into apps) permissively, such as MIT-0 or Zlib, and keep the rest of Fledge AGPL-3.0-or-later; or keep AGPL-3.0-or-later with an exception, in the style of GCC's Runtime Library Exception or PyInstaller's bootloader exception, that lets the runtime files ship inside an app of any license.

**To reverse.** Put the runtime files in their own directory, set their SPDX headers and a `REUSE.toml` annotation to the chosen license (adding its text to `LICENSES/`), and update ADR 001's consequences and the README's license section.

## 2. Is an app a folder with a main.rb?

**Context.** `fledge build` needs to know what an app is: which file starts it, what is on its load path, and what gets copied. LÖVE's answer is a folder with a `main.lua`, and Lota follows it with a folder with a `main.rb`. A Ruby developer might instead expect a gem-like layout (`exe/NAME` and `lib/`), a Gemfile, or a configuration file naming the entry point.

**Default.** An app is a folder with a `main.rb`. The launcher runs `main.rb` with the app's folder on the load path, and `fledge build` copies the whole folder. This is what `exe/fledge`'s help header says.

**To reverse.** Change the launcher's entry point and the folder `fledge build` copies, the help header's FILES section, ADR 001, and Plan 001. Adding a configuration file later that names a different entry point would not break apps laid out this way.

## 3. What provenance statement does fledge --help end with?

**Context.** `exe/fledge` follows `codeslurp`'s help header. Below the header, `codeslurp` carries a declare-ai.org creative statement ("created with significant assistance from Amp, using generative AI. The process was human-controlled through creative prompts."). Fledge is *requested*, not human-controlled line by line, so that statement would not be true of it. `exe/fledge` instead carries a plain-English statement: "Fledge is requested: an AI agent built it, with little or no review from a person. Its gates (tests, linters, and delivery to computers that have never seen Ruby) review it instead." The statement sits below the closing `###`, so `fledge --help` does not print it; only someone reading the source sees it.

**Default.** Keep the plain-English statement, in the source only.

**Options.** Use a declare-ai.org statement that fits requested work, if one does; print the statement as part of `fledge --help`; or move it to the README.

**To reverse.** Edit the comment below the `###` line in `exe/fledge`. To print it, move it above the `###` line; `test/cli_test.rb` asserts it is not printed today, so change that test with it.

## 4. Are -V, and help on standard error for a bare fledge, the CLI conventions you want?

**Context.** `fledge --version` has the short form `-V`, as the help header says, while Lota and Rooibos use `-v`. A bare `fledge` with no arguments prints help to standard error and exits 1, as `git` does, while Lota and Rooibos print usage to standard output and exit 0. Both are public CLI surface, and the frameworks that wrap Fledge may want to match it.

**Default.** `-V`, and help to standard error with exit status 1 for a bare `fledge`, as specified for this skeleton. `-V` leaves `-v` free for a future `--verbose`, as Python's and Rust's tools do.

**To reverse.** Change the matching `when` branches in `Fledge::CLI#call`, the help header in `exe/fledge`, `test/cli_test.rb`, and the CHANGELOG entry.

## 5. What is NAME in dist/NAME-PLATFORM?

**Context.** The help header says `fledge build` writes `DIR/NAME-PLATFORM/`, but not where NAME comes from. It becomes the folder and archive name a person downloads, and on Windows likely the executable's name too.

**Default.** NAME is the app folder's base name (`examples/hello` builds `dist/hello-x86_64-linux/`), as LÖVE's fused games take the developer's chosen file name. The launcher keeps a fixed name inside the folder until this is answered.

**To reverse.** Add a `--name` option or a configuration file, and update the help header and Plan 001.

## 6. Who cuts releases?

**Context.** Releases are git tags and GitHub Releases, never RubyGems.org (ADR 001, section 7). Ferro lets agents run its tag task once the gate and CI pass for a commit. A release publishes runtimes that other people's apps will carry, which is publishing outside the repository.

**Default.** Only the maintainer tags or releases. Agents may push `trunk` once the gate passes, and nothing else.

**To reverse.** Add a scripted tag task, as Ferro's `release:<name>:tag`, and say in AGENTS.md (Releasing) when agents may run it.
