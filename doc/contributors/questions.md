<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. None of these blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## A. What a Fledge version promises about Ruby's version

**Context.** Every runtime of a release carries one Ruby, 4.0.9 today, and Ruby releases a minor version each December that changes what Ruby code sees (default gems become bundled gems, warnings become errors). Under SemVer, a Fledge 1.y that moved its runtimes from Ruby 4.0 to 4.1 would change what a built app holds in a way the app can observe. What a Fledge version promises across versions is product scope (the 1.0 review, `doc/contributors/research/2026-11-04-one-point-oh-surface.md`, section 4.1). ADR 028, which the maintainer read in conversation on 2026-11-03 and called a good first draft, proposes an answer, and its status leaves it for the maintainer to confirm.

**Default.** ADR 028 as drafted, which ADR 029, section 6, applies: a 1.x keeps Ruby 4.0.x and moves only its patch; a later Ruby minor arrives in a minor release as an extra runtime, under the reserved asset name `fledge-runtime-VERSION-ruby-X.Y.Z-PLATFORM.tar.gz`, and becomes the default only in a major. The platform floors (macOS 14, glibc 2.39, iOS 15, Android API 26) are raised only in a major, unless the platform's owner forces it.

**To reverse.** Say that a 1.y may move the default Ruby, or raise a floor, with an entry under "Changed" in the CHANGELOG; agents then amend ADR 028 and ADR 029, section 6, and drop the reserved name if nothing else needs it.

## B. Whether a release from 1.0 on still gets a git tag

**Context.** The maintainer said on 2026-11-03 that from 1.0.0 Fledge is released on RubyGems.org, "not relying on GitHub Releases and git tags" (decisions, 2026-11-03). The schema of `fledge.yml` now names itself by the release's tag (`https://raw.githubusercontent.com/setdef/Fledge/vX.Y.Z/lib/fledge/config.schema.json`, ADR 023, section 3), and ADR 029 freezes that address, so a developer's modeline keeps reading their release's schema after `trunk` moves to the next major. That address exists only if the release's commit is tagged. The words leave open whether "not relying on" means no tag, or a tag the release does not depend on.

**Default.** Every release, 1.0 and later, keeps its tag `vX.Y.Z` on the commit published, pushed by the agent that prepares the release, as Bundler's `rake release` tags each version of a gem it publishes; the release itself, the gem on RubyGems.org, does not depend on it.

**To reverse.** Say that releases from 1.0 have no tag; agents then move the schema's address to one that needs none (a branch per major, or a host of its own), amend ADR 023, section 3, and ADR 029, before 1.0.
