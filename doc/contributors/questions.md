<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. Each question stands alone: it states everything needed to answer it, with no file to open first. None of them blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## A. May a 1.x release change the Ruby inside apps, or raise the minimum operating system?

**Question.** Ruby ships a new minor version every December (4.0 now, 4.1 next), and each one changes what Ruby code sees: default gems become bundled gems, warnings become errors. Fledge puts one Ruby in every app it builds, 4.0.9 today. After 1.0, may a minor release such as 1.5 move that Ruby from 4.0 to 4.1, or raise the oldest operating system Fledge's apps run on (macOS 14, glibc 2.39, iOS 15, Android 8.0), or must either wait for a major release such as 2.0?

**Why it matters.** Developers write `~> 1.2` in a Gemfile. If 1.5 changes their app's Ruby, the update changes behavior they can see in their own app, with no major number to warn them. If majors are the only moment, a developer who wants a newer Ruby must also take every other breaking change.

**You have said** (2026-11-03) that majors ship whenever a breaking change is ready, always after a deprecation notice; that the default Ruby switches only in the first major after Ruby's December release; that a newer Ruby arrives earlier as an opt-in extra runtime in a minor release; that dropping a Ruby minor is a major; and that the last Fledge line to support each Ruby that has not reached end of life gets security fixes until that Ruby does. You called it a good first draft and have not confirmed it as final.

**Default.** That policy: a 1.x keeps Ruby 4.0.x and moves only its patch level. A newer Ruby arrives in a minor release as an extra runtime that a developer selects, and becomes the default only in a major. The operating-system minimums are raised only in a major, unless Apple, Google, or Microsoft forces a change sooner.

**To reverse.** Say that a minor release may move the default Ruby or raise a minimum, with a note under "Changed" in the changelog. Agents then rewrite the version policy and the 1.0 contract to match, and drop the reserved runtime asset name `fledge-runtime-VERSION-ruby-X.Y.Z-PLATFORM.tar.gz` if nothing else needs it.

## B. After 1.0, does a release still get a git tag?

**Question.** You said on 2026-11-03: "Once we hit 1.0.0, we will be releasing via RubyGems (human only), not relying on GitHub Releases and git tags." Does "not relying on" mean releases from 1.0 have no git tag at all, or that they have a tag and nothing depends on it?

**Why it matters.** Each `fledge.yml` points an editor at a JSON Schema by a web address, so the editor can check it. That address now names the release's tag, `https://raw.githubusercontent.com/setdef/Fledge/vX.Y.Z/lib/fledge/config.schema.json`, so a developer's file keeps reading the schema for their Fledge version after `trunk` moves on. The address works only if the release's commit carries that tag.

**Default.** Every release keeps its tag `vX.Y.Z` on the commit that was published, pushed by the agent that prepares the release. The gem on RubyGems.org does not depend on the tag. Bundler's own release task tags each version it publishes the same way.

**To reverse.** Say that releases from 1.0 have no tag. Agents then move the schema's address to one that needs none (a branch for each major version, or a web address of Fledge's own), and update the 1.0 contract before 1.0.
