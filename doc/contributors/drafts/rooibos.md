<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: FYI for Rooibos's session

Not sent, and Fledge needs nothing from it. The maintainer may relay it. Pin: Fledge `v0.0.1.pre.17` (the next release is `v0.1.0`; use the newest tag).

---

For information only: Rooibos's first app builds with Fledge, and you may depend on a tag if you want CI to do it. Rooibos depends on Fledge; Fledge depends on nothing of Rooibos's.

- Put `fledge` in the `development` group of a ship project's Gemfile, pinned by git tag (`gem "fledge", git: "https://github.com/setdef/Fledge", tag: "v0.0.1.pre.17"`), and run `bundle exec fledge build` on a runner of each platform.
- What you may rely on (the command, `fledge.yml`, exit statuses, output) is in `doc/contributors/adr/019.md`.
- A working example workflow, `.github/workflows/wrapper.yml` with `.github/scripts/deliver-tui.py` and `deliver-tui.ps1`, is on branch `experiment/wrapper` of setdef/Fledge, for copying.
