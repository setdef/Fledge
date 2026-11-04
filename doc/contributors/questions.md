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
