<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Draft: FYI for Tokra's session (tokra-cd)

Not sent, and Fledge needs nothing from it. The maintainer may relay it. Release: Fledge `v0.0.1.pre.17` (the next is `v0.1.0`; use the newest tag).

---

For information only: you said packaging needed a bundle id, an AppUserModelID, installers, and Rust extensions. Fledge has all four, and you may depend on a tag of it (`gem "fledge", git: "https://github.com/setdef/Fledge", tag: "..."` in the `development` group). Real code signing waits on accounts.

- `README.md` and its `fledge.yml` section: `kind: windowed`, `name`, `icon`, `version`, and `identifier`.
- `doc/contributors/adr/008.md`: the identifier is the bundle id on macOS and the AppUserModelID on Windows.
- `doc/contributors/adr/009.md`: the installers for each platform.
- `doc/contributors/adr/006.md`: Rust gems built with rb-sys compile as you build.
- `doc/contributors/adr/019.md`: what a wrapper may rely on.
