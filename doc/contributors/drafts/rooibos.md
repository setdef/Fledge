<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: for Rooibos's session

Not sent. The maintainer relays it. Pin: Fledge `v0.0.1.pre.17`.

---

Fledge `v0.0.1.pre.17` is tagged. Needed from Rooibos: CI jobs that build and deliver your first app with it.

- On `arm64-darwin`, `x86_64-linux`, `aarch64-linux`, and `x64-mingw-ucrt`, a build job and a delivery job each. Build on a runner of that platform; deliver on a fresh one with no Ruby.
- A small ship project whose Gemfile has `fledge` in the `development` group, pinned by git tag `v0.0.1.pre.17`.
- A Ruby 4.0 step in the build job, to run Fledge.

A working version is `.github/workflows/wrapper.yml`, with `.github/scripts/deliver-tui.py` and `deliver-tui.ps1`, on branch `experiment/wrapper` of setdef/Fledge (it pins `pre.16`; use `pre.17`). What you may rely on is in `doc/contributors/adr/019.md`.
