<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

This file holds only what agents cannot decide (AGENTS.md, Questions): an apparent conflict with, or ambiguity in, the maintainer's decisions in `decisions.md`, and direction only the maintainer can give. Everything agents invented is theirs to decide, by prior art, in an ADR. None of these blocks work: each names the default the work proceeds on and how to reverse it. When the maintainer answers, quote the answer in `decisions.md`, apply it, and remove the entry.

## D. Whether 1.0 ships with what money cannot prove yet

**Context.** The maintainer ruled on 2026-11-02 that no money is spent now on an Apple Developer account, a Windows signing certificate, or a device cloud (decisions, 2026-11-02). Plan 003 lists three stories as 1.0 that need one: iOS on a real device and App Review, notarization and real trust chains, and Android on arm64. Every other 1.0 story is done, decided, or waiting on another project's repository (a wrapper's own CI). Until the maintainer decides, 1.0 cannot be tagged by Plan 003's own terms.

**Default.** Plan 003's stories keep their **1.0** marks, `v1.0.0` is not tagged, and pre-releases continue as work arrives. Agents take whatever work is free in the meantime.

**To reverse.** Say which of the three stories may be marked **after 1.0** (or which proofs 1.0 may ship without, with the README saying what is unproven); agents then update Plan 003 and, when everything left is done, go on to 1.0.
