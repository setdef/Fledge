<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. None of these blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## A. How is an app laid out, and what is its entry point?

**Context.** Decision 2 asked what the options are besides "a folder with a `main.rb`." The orchestrating agent answered on 2026-10-26 with four options (a folder with a `main.rb`; the executable you already run, such as `exe/my_cool_app`, with the project root where the Gemfile or gemspec is; a configuration file naming the entry point; the gemspec's `executables`), recommending the second with configuration only where needed. Awaiting the maintainer after the orchestrator's answer: the orchestrator reports a reply, which `decisions.md` does not yet quote.

**Default.** An app is a folder with a `main.rb`, which the launcher runs as `ruby main.rb` would (ADR 003). Plan 002's first story builds the recommended layout once the answer is recorded.

**To reverse.** Plan 002, "Ship the executable you already run."

## B. Where does NAME come from?

**Context.** `fledge build` writes `DIR/NAME-PLATFORM/`, and NAME is also the program a person runs. Decision 5: "My instinct is to use the app's primary class/module's name, like MyCoolApp." It depends on entry A, since the project's layout says where that name is found. The orchestrating agent proposed taking it from the gemspec's name or the folder's, camelized, unless configuration names it.

**Default.** NAME is the app folder's name (`examples/hello` builds `dist/hello-PLATFORM/`), until entry A is answered.

**To reverse.** `Fledge::App#name`, with Plan 002's first story.

## C. Should the person's own Ruby environment reach the app and its child processes?

**Context.** Decision 11 asked what was being decided; the orchestrating agent explained it on 2026-10-26: whether to restore the person's own `RUBYOPT`, `GEM_*`, `BUNDLE_*`, and the rest into `ENV` after Ruby has booted, so the app's `ENV` and its child processes look as they would without Fledge, while the app's own boot stays protected. Awaiting the maintainer after the orchestrator's explanation: the orchestrator reports a reply and directed the work below, and `decisions.md` does not yet quote it.

**Default.** Restore, as ADR 003, section 3 describes: the launcher hides those variables from Ruby's boot, pins RubyGems' paths, and puts them back before `main.rb` runs. The parity check and Delivery check it on every platform.

**To reverse.** Remove `restore_environment` and `pin_rubygems` from `runtime/launcher/unix.c` and `windows.c`, and the Gem.path and child-environment checks from `.github/scripts/deliver.sh`, `deliver.ps1`, and `test/built_app_test.rb`.
