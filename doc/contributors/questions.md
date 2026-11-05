<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. Each question stands alone: it states everything needed to answer it, with no file to open first. None of them blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## Reserving Fledge's gem names on RubyGems.org

From 1.0.0 you publish Fledge on RubyGems.org (decisions, 2026-11-03), as ten gems a release builds in CI: `fledge`, which is pure Ruby and depends on `fledge-runtime` at its own version; `fledge-runtime`, pushed once for each of the seven desktop platforms with that platform's runtime inside; and `fledge-runtime-ios` and `fledge-runtime-android`, which carry the phones' runtimes (ADR 030). On 2026-11-04 all four names were free on RubyGems.org (its API answered 404 for each). Anyone can take a free name first. Reserving them means pushing a gem under each from your account now, for example a `0.0.0` that only says Fledge is installed from its git tags until 1.0, which only you can do (AGENTS.md, Releasing); a placeholder stays listed under those names. Do you want the names reserved before 1.0?

The default the work proceeds on: nothing is pushed before 1.0.0, and the names stay unreserved. To reverse it, say so, and an agent prepares the placeholder gems and the `gem push` commands for you to run.
